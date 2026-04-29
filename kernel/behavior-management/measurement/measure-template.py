"""measure_session_quality.py — セッション品質メトリクスの定量測定。

研修案件設計セッションの品質を Before/After で比較するための測定スクリプト。
入力: Claude Code セッションjsonl + 案件 git ログ
出力: メトリクスJSON（撤回回数・失敗パターン再発・応答長・確認系発話数 等）

設計意図（ADR-0006 + training-design-ai-behavior.md の Kill Criteria 自動検出）:
  AI振る舞い仕様（rules_contextual/training-design-ai-behavior.md）が機能しているかを
  定量的に検証するため、セッション後にスクリプトで測定する。手動の自己評価より
  客観性を担保。3回以上再発したら物理制約(pre-tool-use hook)への切り替え判断。

使い方:
  uv run python tools/src/measure_session_quality.py \\
    --jsonl ~/.claude/projects/-Users-nomuraya-workspace-ai-nomuraya-jobs-paiza/<sid>.jsonl \\
    --git-since 2026-04-29 \\
    --label "uluru-2026-04-29" \\
    --output cases/_baselines/uluru-2026-04-29.json

  # ベースラインとの比較
  uv run python tools/src/measure_session_quality.py \\
    --jsonl <PSC session jsonl> \\
    --git-since 2026-XX-XX \\
    --label "psc-2026-XX" \\
    --baseline cases/_baselines/uluru-2026-04-29.json

メトリクス設計:
  - retraction_commits: 「fix:」「撤回」「revert」コミット数（git log）
  - failure_pattern_recurrence: 8パターン別の jsonl キーワード再発カウント
  - confirmation_overuse: AI応答の「進めるか?」「どっちで?」「どうしますか?」出現数
  - long_responses: AI応答で 300tokens 超のメッセージ数
  - user_short_acks: ユーザー応答が「OK」「やろう」「やってくれ」だけの数
  - correction_loops: ユーザー指摘→撤回ペアの数

成果物:
  - メトリクスJSON: 単発測定 or ベースライン比較
  - stdout: 人間可読サマリ
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# 失敗パターン検出キーワード（training-design-ai-behavior.md の Kill Criteria と整合）
FAILURE_PATTERNS = {
    "受講生サポート役強要": re.compile(
        r"(上位者.*(フォロー|サポート|引っ張)|テックリード.*受講生|"
        r"hi=.*担当|ken=.*担当|個別ペアリング|"
        r"上位者.*下位者を)",
        re.IGNORECASE,
    ),
    "章番号参照": re.compile(r"STEP\s*[0-9]+\s*-\s*[0-9]+", re.IGNORECASE),
    "分単位タイムテーブル": re.compile(
        r"\d{1,2}:\d{2}-\d{1,2}:\d{2}\s*\|.*【(環境構築|講義)\s*\d+】"
    ),
    "観測不可能ゴール": re.compile(
        r"(心構え|心がけ|意識を持つ|姿勢を学ぶ|理解する状態(を|に))"
    ),
    "受講生情報の遅い参照": re.compile(
        r"(PHP未経験者向け|完全初学者前提|事前学習を確認していない)"
    ),
    "確認系過多": re.compile(
        r"(進めるか[?？]|どっちで(進める|行く)[?？]|どうしますか[?？]|"
        r"どちらが(よろしい|いい)[?？]|どこから(始めま|やりま)す[?？]|"
        r"実装するか[?？]|修正実装するか[?？]|再実装するか[?？]|"
        r"推奨.*即実装|即実装で進める|"
        r"どうする[?？]|やるか[?？])"
    ),
    "粒度往復": re.compile(r"(\d+行→\d+行→\d+行|もっと(粗く|細かく).*戻す)"),
    "横断メンテ漏れ": re.compile(r"(STEP数の更新|章番号.*更新|参照.*陳腐化)"),
}

CONFIRMATION_RE = re.compile(
    r"(進めるか[?？]|どっちで(進める|行く)[?？]|どうしますか[?？]|"
    r"どちらが(よろしい|いい)[?？]|どこから(始めま|やりま)す[?？]|"
    r"実装するか[?？]|修正実装するか[?？]|再実装するか[?？]|"
    r"推奨.*即実装|即実装で進める|"
    r"進めて(よい|いい)?か[?？]|"
    r"どうする[?？]|やるか[?？]|"
    r"どっち(で|を選)|どちら(で|が|を選))"
)

USER_SHORT_ACK_RE = re.compile(
    r"^\s*(OK|ok|はい|やろう|やってくれ|了解|よろ(しく)?|いいよ)\s*[。．.！!]?\s*$"
)


def parse_jsonl(path: Path) -> dict:
    """セッションjsonl をパースしてメッセージ配列とtool使用配列を返す."""
    user_msgs: list[dict] = []
    ai_msgs: list[dict] = []
    tool_uses: list[dict] = []  # assistant message内のtool_use を抽出
    with open(path) as f:
        for line in f:
            try:
                e = json.loads(line)
            except Exception:
                continue
            t = e.get("type")
            if t == "user" and not e.get("isSidechain"):
                msg = e.get("message", {}).get("content", "")
                if isinstance(msg, list):
                    texts = [
                        c.get("text", "")
                        for c in msg
                        if isinstance(c, dict) and c.get("type") == "text"
                    ]
                    msg = "\n".join(texts)
                if not msg or "<system-reminder>" in str(msg)[:50]:
                    continue
                user_msgs.append({"timestamp": e.get("timestamp", ""), "text": str(msg)})
            elif t == "assistant" and not e.get("isSidechain"):
                content = e.get("message", {}).get("content", "")
                if isinstance(content, list):
                    texts = []
                    for c in content:
                        if not isinstance(c, dict):
                            continue
                        if c.get("type") == "text":
                            texts.append(c.get("text", ""))
                        elif c.get("type") == "tool_use":
                            tool_uses.append({
                                "timestamp": e.get("timestamp", ""),
                                "name": c.get("name", ""),
                                "input": c.get("input", {}),
                            })
                    msg = "\n".join(texts)
                else:
                    msg = str(content)
                if not msg:
                    continue
                ai_msgs.append({"timestamp": e.get("timestamp", ""), "text": str(msg)})
    return {"user": user_msgs, "ai": ai_msgs, "tool_uses": tool_uses}


def count_failure_pattern_recurrence(ai_msgs: list[dict]) -> dict:
    """AI応答内の失敗パターン出現数をカウント."""
    counts: dict[str, int] = {}
    for name, pat in FAILURE_PATTERNS.items():
        c = 0
        for m in ai_msgs:
            c += len(pat.findall(m["text"]))
        counts[name] = c
    return counts


def count_confirmation_overuse(ai_msgs: list[dict]) -> int:
    return sum(len(CONFIRMATION_RE.findall(m["text"])) for m in ai_msgs)


def count_long_responses(ai_msgs: list[dict], threshold: int = 300) -> dict:
    """AI応答の長さ統計（threshold以上をlong扱い）.

    推定トークン数: 文字数 / 2 (日本語+英語混在の経験則).
    """
    long_count = 0
    long_lengths: list[int] = []
    all_lengths: list[int] = []
    for m in ai_msgs:
        n = len(m["text"]) // 2  # 粗い推定
        all_lengths.append(n)
        if n > threshold:
            long_count += 1
            long_lengths.append(n)
    avg = sum(all_lengths) / len(all_lengths) if all_lengths else 0
    return {
        "long_count": long_count,
        "total_count": len(ai_msgs),
        "avg_estimated_tokens": int(avg),
        "max_estimated_tokens": max(all_lengths) if all_lengths else 0,
    }


def count_user_short_acks(user_msgs: list[dict]) -> int:
    """ユーザー応答が短い承認だけだった回数."""
    return sum(1 for m in user_msgs if USER_SHORT_ACK_RE.match(m["text"].strip()))


def run_git_log(repo_path: Path, since: str) -> list[str]:
    """git log の subject を since 以降で取得."""
    try:
        out = subprocess.run(
            [
                "git",
                "-C",
                str(repo_path),
                "log",
                f"--since={since}",
                "--pretty=format:%s",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        return out.stdout.strip().splitlines()
    except Exception as e:
        print(f"WARN: git log failed: {e}", file=sys.stderr)
        return []


def count_retraction_commits(commits: list[str]) -> dict:
    """撤回・修正コミットを分類."""
    fix_count = sum(1 for c in commits if c.startswith("fix:"))
    revert_count = sum(1 for c in commits if c.startswith("revert") or "revert" in c.lower())
    retraction_count = sum(
        1 for c in commits if "撤回" in c or "全面撤回" in c or "やり直し" in c
    )
    return {
        "fix_commits": fix_count,
        "revert_commits": revert_count,
        "retraction_commits": retraction_count,
        "total_commits": len(commits),
    }


def count_design_quality_metrics(tool_uses: list[dict]) -> dict:
    """設計品質指標（着手前のデータ揃え）.

    case-readiness-checklist.md の6カテゴリ（A〜F）に基づき、
    AIが着手前にどれだけのデータを Read したかを測る。
    効率指標とは別に「設計の正しさの前提条件」を測る軸。
    """
    student_info_reads = 0  # A 受講生情報
    case_constraint_reads = 0  # B 案件先制約（CURRICULUM_DESIGN.md期間/時間）
    past_case_reads = 0  # D 過去案件
    adr_reads = 0  # E 設計根拠（ADR）
    principles_reads = 0  # E 設計根拠（原則・思考エンジン）
    paiza_csv_reads = 0  # A 受講生情報（forTEAM CSV）
    data_driven_judgment = 0  # practice_count / groups の参照

    for t in tool_uses:
        name = t.get("name", "")
        inp = t.get("input", {}) if isinstance(t.get("input"), dict) else {}
        cmd = str(inp.get("command", "")) if name == "Bash" else ""
        path = str(inp.get("file_path", "")) if name in ("Read", "Edit", "Write") else ""

        if name == "Read":
            if "CURRICULUM_DESIGN.md" in path:
                # 受講生情報節を含む可能性が高い
                student_info_reads += 1
                case_constraint_reads += 1
            if "raw/internal" in path and "paiza" in path and ".csv" in path:
                paiza_csv_reads += 1
            if re.search(r"cases/202[0-9]-[0-9]+-(?!.*/derived/intermediate/$)", path):
                # 過去案件のディレクトリ Read（自案件以外）
                past_case_reads += 1
            if "/docs/adr/" in path:
                adr_reads += 1
            if any(
                kw in path
                for kw in [
                    "training-design-principles.md",
                    "training-thinking-engine.md",
                    "training-design-ai-behavior.md",
                    "curriculum-design-flow.md",
                    "case-readiness-checklist.md",
                ]
            ):
                principles_reads += 1
        elif name == "Bash":
            if "practice_count" in cmd or "groups" in cmd:
                data_driven_judgment += 1
            if "parse_paiza_csv" in cmd:
                paiza_csv_reads += 1
            if re.search(r"grep.*-r.*cases/202[0-9]", cmd):
                past_case_reads += 1

    return {
        "student_info_reads": student_info_reads,
        "case_constraint_reads": case_constraint_reads,
        "paiza_csv_reads": paiza_csv_reads,
        "past_case_reads": past_case_reads,
        "adr_reads": adr_reads,
        "principles_reads": principles_reads,
        "data_driven_judgment_count": data_driven_judgment,
        "data_readiness_score": (
            min(student_info_reads, 1) * 20  # A 必須
            + min(case_constraint_reads, 1) * 15  # B 必須
            + min(paiza_csv_reads, 1) * 10  # A 補助
            + min(past_case_reads, 1) * 15  # D
            + min(adr_reads, 1) * 15  # E
            + min(principles_reads, 1) * 15  # E
            + min(data_driven_judgment, 1) * 10  # 自動化原則
        ),  # 0-100点
    }


def count_lms_mapping_metrics(tool_uses: list[dict]) -> dict:
    """LMS course-mondai マッピング関連の時間消費指標.

    本セッション最大の時間消費領域はLMS構造とカリキュラムの対応マッピング。
    ツール使用パターンから測定する。
    """
    # paiza HTML fetch（curl/WebFetch/urlopen）
    paiza_fetch_count = 0
    # lms_*.py スクリプトの実行回数
    lms_script_runs = 0
    # lms/courses/ や lms/mondai/ の Read 回数
    lms_data_reads = 0
    # curriculum_edit / apply_curriculum 実行回数（マッピング判断の確定）
    curriculum_tool_runs = 0
    # シート read（既存マッピング確認）
    sheet_reads = 0

    for t in tool_uses:
        name = t.get("name", "")
        inp = t.get("input", {}) if isinstance(t.get("input"), dict) else {}
        cmd = str(inp.get("command", "")) if name == "Bash" else ""
        path = str(inp.get("file_path", "")) if name in ("Read", "Edit", "Write") else ""
        url = str(inp.get("url", "")) if name == "WebFetch" else ""

        if name == "WebFetch" and "paiza.jp" in url:
            paiza_fetch_count += 1
        elif name == "Bash" and ("paiza.jp" in cmd and ("curl" in cmd or "urlopen" in cmd)):
            paiza_fetch_count += 1
        elif name == "Bash" and "lms_" in cmd and ".py" in cmd:
            lms_script_runs += 1
        elif name == "Read" and ("lms/courses/" in path or "lms/mondai/" in path):
            lms_data_reads += 1
        elif name == "Bash" and ("curriculum_edit.py" in cmd or "apply_curriculum" in cmd or "apply.py task curriculum" in cmd):
            curriculum_tool_runs += 1
        elif name == "Bash" and ("sheets_client" in cmd or "read_range" in cmd):
            sheet_reads += 1

    return {
        "paiza_fetch_count": paiza_fetch_count,
        "lms_script_runs": lms_script_runs,
        "lms_data_reads": lms_data_reads,
        "curriculum_tool_runs": curriculum_tool_runs,
        "sheet_reads": sheet_reads,
        "total_lms_mapping_actions": (
            paiza_fetch_count + lms_script_runs + lms_data_reads
            + curriculum_tool_runs + sheet_reads
        ),
    }


def count_mapping_revision_commits(commits: list[str]) -> dict:
    """マッピング判断の修正コミット数.

    必須/追加振り分け変更・C列/D列表記変更・LMS構造修正の commit を分類。
    """
    required_optional_revisions = sum(
        1 for c in commits
        if any(kw in c for kw in ["必須", "追加問題"]) and c.startswith("fix:")
    )
    column_revisions = sum(
        1 for c in commits if any(kw in c for kw in ["C列", "D列", "E列"])
    )
    lms_struct_revisions = sum(
        1 for c in commits
        if any(kw in c for kw in ["lms_course", "lms_mondai", "practice_count", "groups"])
    )
    title_mismatch_fixes = sum(
        1 for c in commits if "タイトル" in c and ("修正" in c or "不一致" in c or c.startswith("fix:"))
    )
    return {
        "required_optional_revisions": required_optional_revisions,
        "column_revisions": column_revisions,
        "lms_struct_revisions": lms_struct_revisions,
        "title_mismatch_fixes": title_mismatch_fixes,
        "total_mapping_revisions": (
            required_optional_revisions + column_revisions
            + lms_struct_revisions + title_mismatch_fixes
        ),
    }


def count_correction_loops(user_msgs: list[dict], ai_msgs: list[dict]) -> int:
    """ユーザー指摘→AI撤回ペアの数（粗い推定）."""
    correction_keywords_user = re.compile(
        r"(違う|違います|それは|あるべき姿|問題|矛盾|"
        r"撤回|やり直し|逆|反対|誤り|間違)"
    )
    retraction_keywords_ai = re.compile(
        r"(指摘が正しい|撤回します|認めます|誤りでした|"
        r"全面撤回|前提誤り|やり直し)"
    )
    user_corrections = sum(
        1 for m in user_msgs if correction_keywords_user.search(m["text"])
    )
    ai_retractions = sum(
        1 for m in ai_msgs if retraction_keywords_ai.search(m["text"])
    )
    return min(user_corrections, ai_retractions)


def measure(jsonl_path: Path, repo_path: Path, since: str, label: str, case_period_days: int | None = None) -> dict:
    msgs = parse_jsonl(jsonl_path)
    commits = run_git_log(repo_path, since)
    lms = count_lms_mapping_metrics(msgs.get("tool_uses", []))
    result = {
        "label": label,
        "jsonl_path": str(jsonl_path),
        "since": since,
        "case_period_days": case_period_days,
        "measured_at": datetime.now().isoformat(),
        "message_counts": {
            "user_messages": len(msgs["user"]),
            "ai_messages": len(msgs["ai"]),
            "tool_uses": len(msgs.get("tool_uses", [])),
        },
        # === 設計品質: データ揃え（着手前の前提条件）===
        "design_quality_metrics": count_design_quality_metrics(msgs.get("tool_uses", [])),
        # === 主要指標: LMS course-mondai マッピング（時間消費の本丸）===
        "lms_mapping_metrics": lms,
        "mapping_revision_metrics": count_mapping_revision_commits(commits),
        # === 副次指標: 失敗パターン・対話品質（含: 倫理Kill Criteria）===
        "failure_pattern_recurrence": count_failure_pattern_recurrence(msgs["ai"]),
        "confirmation_overuse": count_confirmation_overuse(msgs["ai"]),
        "long_responses": count_long_responses(msgs["ai"]),
        "user_short_acks": count_user_short_acks(msgs["user"]),
        "correction_loops": count_correction_loops(msgs["user"], msgs["ai"]),
        "git_metrics": count_retraction_commits(commits),
    }
    # 期間正規化（1日あたり）— 案件期間が指定されていれば算出
    if case_period_days and case_period_days > 0:
        total = lms["total_lms_mapping_actions"]
        result["lms_mapping_per_day"] = round(total / case_period_days, 2)
    return result


def compare_with_baseline(current: dict, baseline_path: Path) -> dict:
    with open(baseline_path) as f:
        baseline = json.load(f)
    diff = {}
    for key in ["confirmation_overuse", "user_short_acks", "correction_loops"]:
        if key in current and key in baseline:
            diff[key] = {
                "baseline": baseline[key],
                "current": current[key],
                "delta": current[key] - baseline[key],
            }
    for nested_key in [
        "failure_pattern_recurrence",
        "git_metrics",
        "lms_mapping_metrics",
        "mapping_revision_metrics",
        "design_quality_metrics",
    ]:
        if nested_key in current:
            diff[nested_key] = {}
            for k, v in current[nested_key].items():
                base_v = baseline.get(nested_key, {}).get(k, 0)
                diff[nested_key][k] = {
                    "baseline": base_v,
                    "current": v,
                    "delta": v - base_v,
                }
    return diff


def print_summary(result: dict) -> None:
    print(f"=== Session Quality: {result['label']} ===")
    print(f"  jsonl: {result['jsonl_path']}")
    print(f"  ユーザーメッセージ: {result['message_counts']['user_messages']}")
    print(f"  AI応答: {result['message_counts']['ai_messages']}")
    print(f"  ツール使用: {result['message_counts'].get('tool_uses', 0)}")

    # === 設計品質: データ揃え ===
    print("\n  🟢 設計品質指標（着手前データ揃え・case-readiness-checklist.md）:")
    dq = result["design_quality_metrics"]
    score = dq["data_readiness_score"]
    score_marker = "✅" if score >= 70 else "⚠️" if score >= 40 else "❌"
    print(f"    → data_readiness_score: {score}/100 {score_marker}")
    for k, v in dq.items():
        if k != "data_readiness_score":
            print(f"      {k}: {v}")

    # === 主要指標: LMS マッピング（時間消費の本丸）===
    print("\n  🔵 LMS course-mondai マッピング指標 (主要・時間消費の本丸):")
    lms = result["lms_mapping_metrics"]
    for k, v in lms.items():
        marker = "  " if k != "total_lms_mapping_actions" else "→"
        print(f"    {marker} {k}: {v}")
    if result.get("case_period_days"):
        per_day = result.get("lms_mapping_per_day", 0)
        print(f"    📊 期間正規化（1日あたり）: {per_day}回/日 ({result['case_period_days']}日間)")

    print("\n  🔵 マッピング判断の修正コミット:")
    rev = result["mapping_revision_metrics"]
    for k, v in rev.items():
        marker = "  " if k != "total_mapping_revisions" else "→"
        print(f"    {marker} {k}: {v}")

    # === 副次指標 ===
    print(f"\n  確認系過多発（進めるか?等）: {result['confirmation_overuse']}回")
    lr = result["long_responses"]
    print(
        f"  長文応答(>300tokens推定): {lr['long_count']}/{lr['total_count']}件 "
        f"(平均{lr['avg_estimated_tokens']} / 最大{lr['max_estimated_tokens']})"
    )
    print(f"  ユーザー短承認応答: {result['user_short_acks']}回")
    print(f"  補正ループ: {result['correction_loops']}回")
    print(f"  Gitコミット (since={result['since']}):")
    for k, v in result["git_metrics"].items():
        print(f"    {k}: {v}")

    # 倫理Kill Criteria（別カテゴリ・最重要）
    print("\n  ⚖️  倫理Kill Criteria（再発1回でも即停止判断）:")
    ethics_v = result["failure_pattern_recurrence"].get("受講生サポート役強要", 0)
    marker = "❌" if ethics_v >= 1 else "✅"
    print(f"    {marker} 受講生サポート役強要: {ethics_v}回")

    print("\n  失敗パターン再発（その他）:")
    for k, v in result["failure_pattern_recurrence"].items():
        if k == "受講生サポート役強要":
            continue
        marker = "❌" if v >= 3 else "⚠️" if v >= 1 else "✅"
        print(f"    {marker} {k}: {v}回")

    # Kill Criteria 総合判定
    if ethics_v >= 1:
        print("\n  🔴 倫理Kill Criteria発動: 受講生サポート役強要 1回以上 → 即停止判断")
    other_max = max(
        (v for k, v in result["failure_pattern_recurrence"].items() if k != "受講生サポート役強要"),
        default=0,
    )
    if other_max >= 3:
        print("  🔴 機能Kill Criteria発動: 失敗パターン3回以上再発 → 該当節の強化検討")
    elif other_max >= 1:
        print("  🟡 注意: 失敗パターン1回以上再発 → 次セッションで監視")


def print_diff(diff: dict) -> None:
    print("\n=== Baseline Comparison ===")
    for category, data in diff.items():
        if isinstance(data, dict) and "delta" in data:
            sign = "+" if data["delta"] > 0 else ""
            print(f"  {category}: {data['baseline']} → {data['current']} ({sign}{data['delta']})")
        elif isinstance(data, dict):
            print(f"  {category}:")
            for k, v in data.items():
                sign = "+" if v.get("delta", 0) > 0 else ""
                print(f"    {k}: {v['baseline']} → {v['current']} ({sign}{v['delta']})")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--jsonl", required=True, type=Path)
    p.add_argument("--git-since", required=True, help="例: 2026-04-29")
    p.add_argument("--repo", default=None, help="git repo path（省略時 repo_root自動）")
    p.add_argument("--label", required=True, help="例: uluru-2026-04-29")
    p.add_argument("--output", type=Path, default=None, help="JSON出力先")
    p.add_argument("--baseline", type=Path, default=None, help="比較用ベースラインJSON")
    p.add_argument(
        "--days",
        type=int,
        default=None,
        help="案件期間（日数）。指定すると1日あたりの正規化値を出力。例: うるるは20日",
    )
    args = p.parse_args()

    repo_path = args.repo or Path(__file__).resolve().parent.parent.parent
    if not Path(repo_path).is_dir():
        sys.exit(f"❌ repo not found: {repo_path}")

    if not args.jsonl.exists():
        sys.exit(f"❌ jsonl not found: {args.jsonl}")

    result = measure(args.jsonl, Path(repo_path), args.git_since, args.label, case_period_days=args.days)
    print_summary(result)

    if args.baseline and args.baseline.exists():
        diff = compare_with_baseline(result, args.baseline)
        print_diff(diff)
        result["baseline_diff"] = diff

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with open(args.output, "w") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print(f"\n✅ saved: {args.output}")


if __name__ == "__main__":
    main()
