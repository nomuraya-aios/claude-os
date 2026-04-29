"""common-patterns.py — 全ドメイン共通の発話禁止パターン.

各ドメイン固有の Stop hook（stop-<domain>-alert.py）はこのモジュールから
COMMON_FORBIDDEN_PATTERNS をインポートして、ドメイン固有パターンと結合する。

設計意図:
  - core.md §1.1 の発話禁止リストをコード化
  - 重複削減（各 hook で同じ正規表現を書かない）
  - 一元更新（パターン追加が即時に全ドメインに反映）

形成セッション: 2026-04-29 paiza/training-design ドメインで
            自己申告1回 vs 客観測定11件（1100%乖離）が判明したパターンを汎用化.

使い方:
  ```python
  from common_patterns import COMMON_FORBIDDEN_PATTERNS, COMMON_SELF_EXCLUSION

  # ドメイン固有 Stop hook で:
  ALL_PATTERNS = COMMON_FORBIDDEN_PATTERNS + DOMAIN_SPECIFIC_PATTERNS
  ```
"""
from __future__ import annotations

import re

# 全ドメイン共通の発話禁止パターン（core.md §1.1 と整合）
COMMON_FORBIDDEN_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    # 実装確認
    (re.compile(r"実装するか[?？]"), "「実装するか?」"),
    (re.compile(r"修正実装するか[?？]"), "「修正実装するか?」"),
    (re.compile(r"再実装するか[?？]"), "「再実装するか?」"),
    # 進行確認
    (re.compile(r"進めるか[?？]"), "「進めるか?」"),
    (re.compile(r"進めて(よい|いい)?か[?？]"), "「進めてよいか?」"),
    # 推奨直後の確認（核となる違反パターン）
    (re.compile(r"推奨.*即実装"), "「推奨は即実装」"),
    (re.compile(r"即実装で進める"), "「即実装で進める」"),
    # 選択肢誘発
    (re.compile(r"どっちで(進める|行く)?[?？]"), "「どっちで?」"),
    (re.compile(r"どちら(で|が)(よろしい|いい)?[?？]"), "「どちらで?」"),
    (re.compile(r"どこから(始めま|やりま)す[?？]"), "「どこから始める?」"),
    # 動作確認（リスク高操作以外）
    (re.compile(r"どうする[?？]"), "「どうする?」"),
    (re.compile(r"やるか[?？]"), "「やるか?」"),
    (re.compile(r"どうしますか[?？]"), "「どうしますか?」"),
]

# 自己排除パターン（警告メッセージ自身の引用を誤検知しないため）
# このキーワードを含む行はパターン検出の対象外
COMMON_SELF_EXCLUSION: list[str] = [
    "core.md §1",  # core 仕様への参照
    "発話禁止リスト",  # 仕様書の引用
    "common-patterns.py",  # 本ファイル自身
    "stop-confirmation",  # paiza 既存実装
    "stop-alert-template",  # テンプレート参照
    "training-design-ai-behavior",  # paiza 既存仕様参照
    "禁句リスト",  # 仕様書の引用
    "Kill Criteria",  # Kill Criteria 議論内
]


def detect_forbidden_patterns(
    msg: str,
    domain_patterns: list[tuple[re.Pattern[str], str]] | None = None,
    domain_self_exclusion: list[str] | None = None,
) -> list[str]:
    """応答メッセージから発話禁止パターンを検出.

    Args:
        msg: AI の応答メッセージ全文
        domain_patterns: ドメイン固有の追加パターン（任意）
        domain_self_exclusion: ドメイン固有の自己排除キーワード（任意）

    Returns:
        検出されたパターンのラベルリスト（重複あり、行ごとにカウント）
    """
    all_patterns = COMMON_FORBIDDEN_PATTERNS + (domain_patterns or [])
    all_exclusion = COMMON_SELF_EXCLUSION + (domain_self_exclusion or [])

    detected: list[str] = []
    for line in msg.splitlines():
        # 自己排除: 該当キーワードを含む行はスキップ
        if any(kw in line for kw in all_exclusion):
            continue
        for pat, label in all_patterns:
            if pat.search(line):
                detected.append(label)
                break  # 1行1検出
    return detected


def build_alert_message(detected: list[str], domain: str = "") -> str:
    """検出結果から AI へのアラートメッセージを構築.

    Args:
        detected: detect_forbidden_patterns() の戻り値
        domain: ドメイン名（任意・メッセージに含める）

    Returns:
        additionalContext として AI に注入する警告テキスト
    """
    domain_suffix = f"（{domain} ドメイン）" if domain else ""
    labels_str = ", ".join(sorted(set(detected)))
    return f"""⚠️ 発話禁止リスト違反を検出 (core.md §1.1 違反){domain_suffix}

直前の応答に発話禁止パターンが {len(detected)} 件検出されました: {labels_str}

core.md §1 即時実行プロトコルに従い、次の応答では:
- ❌「実装するか?」「進めるか?」「推奨は即実装」を **使わない**
- ✅ 提案を出すなら **そのまま実行** → 結果報告フォーマット（「✅ 実装した」）

自己評価は楽観的になりがちです（実証データ: 自己申告1回 vs 実測11件、1100%乖離）。
**ユーザーへの確認** が本当に必要か（リスク高操作・事業判断・嗜好など）を自問してから出力してください。"""


if __name__ == "__main__":
    # テスト用 self-check
    test_msg = "実装するか? 推奨は即実装で進める。"
    detected = detect_forbidden_patterns(test_msg)
    print(f"Detected: {detected}")
    print(build_alert_message(detected, domain="test"))
