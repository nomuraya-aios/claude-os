#!/bin/bash
# PostToolUse Hook: .plist ファイル編集時の運用安全性チェック
#
# なぜ必要か:
#   2026-04-16 セッションで launchd plist に oh-dispatch (LLM呼び出し) を登録し、
#   自分で書いた no-anthropic-api-background.md ルールに違反した。
#   「書いて満足」を防ぐため、plist 編集時に自動で運用リスクを検出する。
#
# チェック内容:
#   1. StartCalendarInterval があるのに RunAtLoad が未設定
#   2. 参照先スクリプトが LLM を呼び出すか（oh-dispatch, claude, curl API等）
#   3. 参照先スクリプトに set -euo pipefail があるか

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
    exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# .plist のみ対象
if [[ "$FILE_PATH" != *.plist ]]; then
    exit 0
fi

ISSUES=""

# --- Check 1: StartCalendarInterval + RunAtLoad ---
if grep -q "StartCalendarInterval" "$FILE_PATH" 2>/dev/null; then
    if ! grep -q "<key>RunAtLoad</key>" "$FILE_PATH" 2>/dev/null; then
        ISSUES="${ISSUES}## スケジュール設定の問題\n"
        ISSUES="${ISSUES}StartCalendarInterval があるのに RunAtLoad が未設定です。\n"
        ISSUES="${ISSUES}macOS は OnDemand=true に自動設定し、スケジュール実行が無効化されます。\n"
        ISSUES="${ISSUES}→ \`<key>RunAtLoad</key><false/>\` を追加してください。\n\n"
    fi
fi

# --- Check 2: 参照先スクリプトの LLM 呼び出し検出 ---
# ProgramArguments からスクリプトパスを抽出
SCRIPT_PATH=$(grep -A1 "<string>/.*\.sh</string>" "$FILE_PATH" 2>/dev/null \
    | grep -o '/[^<]*\.sh' | head -1)

if [[ -n "$SCRIPT_PATH" ]] && [[ -f "$SCRIPT_PATH" ]]; then
    # スクリプト本体と、sourceしているファイルも含めて検索
    LLM_PATTERNS="oh-dispatch|claude -p|claude --print|openrouter\.ai/api|api\.anthropic\.com|api\.openai\.com|moltbook_llm_call|moltbook_oh_dispatch"

    LLM_HITS=$(grep -n -E "$LLM_PATTERNS" "$SCRIPT_PATH" 2>/dev/null | head -5)
    if [[ -n "$LLM_HITS" ]]; then
        ISSUES="${ISSUES}## ⚠️ LLM呼び出しを含むスクリプトがlaunchdに登録されています\n"
        ISSUES="${ISSUES}参照先: ${SCRIPT_PATH}\n"
        ISSUES="${ISSUES}検出箇所:\n\`\`\`\n${LLM_HITS}\n\`\`\`\n"
        ISSUES="${ISSUES}→ no-anthropic-api-background.md ルール: バックグラウンドでのLLM呼び出しは原則禁止\n"
        ISSUES="${ISSUES}→ LLMを使わない処理（collect, status等）に変更するか、例外登録が必要です\n\n"
    fi

    # --- Check 3: set -euo pipefail ---
    if ! head -5 "$SCRIPT_PATH" | grep -q 'set -.*e.*u.*o pipefail\|set -euo pipefail'; then
        ISSUES="${ISSUES}## スクリプトに set -euo pipefail がありません\n"
        ISSUES="${ISSUES}参照先: ${SCRIPT_PATH}\n"
        ISSUES="${ISSUES}→ launchd で実行されるスクリプトには必須です\n\n"
    fi
fi

# --- 結果出力 ---
if [ -n "$ISSUES" ]; then
    echo "[launchd-check] ${FILE_PATH} に運用リスクがあります。"
    echo ""
    echo -e "$ISSUES"
fi

exit 0
