#!/usr/bin/env python3
"""Stop hook: 確認系過多発（「実装するか?」「推奨は即実装」等）を検出して AI に警告.

---
rule_id: confirmation-overuse-alert
enforces: [training-design-ai-behavior-3.2.1]
event: Stop
matcher: null
action: inject
when_matches: assistant response contains confirmation-overuse patterns
priority: high
changelog_ref: 2026-04-30 新設（うるるセッションで自己申告1回/実測11回乖離発覚）
---

paiza repo (~/workspace-ai/nomuraya-jobs/paiza) で作業中の AI 応答テキストを検査し、
training-design-ai-behavior.md §3.2.1 発話禁止リストのパターンが含まれていたら、
次ターンの additionalContext で AI に書き直しを促す。

スコープ: paiza repo 配下のみ発動（全プロジェクトに広げると過剰）。

検出パターン:
  - 「実装するか?」「修正実装するか?」「再実装するか?」
  - 「進めるか?」「進めて(よい|いい)?か?」
  - 「推奨は即実装」「即実装で進める」
  - 「どっちで?」「どちらで?」
  - 「どうする?」「やるか?」
  - 「？/?」で終わる行に「推奨」が含まれる

無限ループ防止:
  - stop_hook_active 時はスキップ
  - 警告メッセージ自身が「実装するか?」を含んでいても誤検知しない（self-exclusion）
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / ".claude/lib"))
from hook_base import log_fire  # noqa: E402

HOOK_NAME = Path(__file__).stem
RULE_ID = "confirmation-overuse-alert"

# scope: paiza repo 配下のみ
PAIZA_REPO_PATH = Path.home() / "workspace-ai/nomuraya-jobs/paiza"

# 発話禁止リスト（measure_session_quality.py の CONFIRMATION_RE と同期）
CONFIRMATION_PATTERNS = [
    (re.compile(r"実装するか[?？]"), "「実装するか?」"),
    (re.compile(r"修正実装するか[?？]"), "「修正実装するか?」"),
    (re.compile(r"再実装するか[?？]"), "「再実装するか?」"),
    (re.compile(r"進めるか[?？]"), "「進めるか?」"),
    (re.compile(r"進めて(よい|いい)?か[?？]"), "「進めてよいか?」"),
    (re.compile(r"推奨.*即実装"), "「推奨は即実装」"),
    (re.compile(r"即実装で進める"), "「即実装で進める」"),
    (re.compile(r"どっちで(進める|行く)?[?？]"), "「どっちで?」"),
    (re.compile(r"どちら(で|が)(よろしい|いい)?[?？]"), "「どちらで?」"),
    (re.compile(r"どうする[?？]"), "「どうする?」"),
    (re.compile(r"やるか[?？]"), "「やるか?」"),
    (re.compile(r"どうしますか[?？]"), "「どうしますか?」"),
]


def detect_confirmation_overuse(msg: str) -> list[str]:
    """応答メッセージから確認系過多発パターンを検出.

    自己排除: 警告メッセージ自身（本ファイルのテキスト）の引用は除外する。
    具体的には「§3.2.1」「発話禁止リスト」を含む行はスキップ。
    """
    detected: list[str] = []
    for line in msg.splitlines():
        # 自己排除: 警告メッセージ自身を含む行はスキップ
        if "§3.2.1" in line or "発話禁止リスト" in line or "training-design-ai-behavior" in line:
            continue
        if "stop-confirmation-overuse-alert" in line:
            continue
        for pat, label in CONFIRMATION_PATTERNS:
            if pat.search(line):
                detected.append(label)
                break
    return detected


def is_in_paiza_repo() -> bool:
    """現在の cwd が paiza repo 配下か."""
    cwd = Path(os.getcwd()).resolve()
    try:
        cwd.relative_to(PAIZA_REPO_PATH.resolve())
        return True
    except ValueError:
        return False


ALERT_TEMPLATE = """⚠️ 確認系過多発を検出 (training-design-ai-behavior.md §3.2.1 違反)

直前の応答に発話禁止パターンが {count} 件検出されました: {labels}

§3.2.1 即時実行プロトコルに従い、次の応答では:
- ❌「実装するか?」「進めるか?」「推奨は即実装」を **使わない**
- ✅ 提案を出すなら **そのまま実行** → 結果報告フォーマット（「✅ 実装した」）

自己評価は楽観的になりがちです（うるるセッション実測: 自己申告1回 vs 実測11件、1100%乖離）。
**ユーザーへの確認** が本当に必要か（リスク高操作・事業判断・嗜好など）を自問してから出力してください。"""


def main() -> int:
    raw = sys.stdin.read()
    if not raw:
        return 0
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return 0

    if data.get("stop_hook_active"):
        return 0

    if not is_in_paiza_repo():
        return 0

    msg = data.get("assistant_message", "") or ""
    if not msg:
        return 0

    detected = detect_confirmation_overuse(msg)
    if not detected:
        return 0

    # 検出時、additionalContext で警告を注入
    feedback = {
        "hookSpecificOutput": {
            "hookEventName": "Stop",
            "additionalContext": ALERT_TEMPLATE.format(
                count=len(detected),
                labels=", ".join(sorted(set(detected))),
            ),
        }
    }
    print(json.dumps(feedback, ensure_ascii=False))
    log_fire(HOOK_NAME, rule_id=RULE_ID, matched=True, action="inject")
    return 0


if __name__ == "__main__":
    sys.exit(main())
