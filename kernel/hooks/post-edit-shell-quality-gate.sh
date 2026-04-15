#!/bin/bash
# PostToolUse Hook: .sh ファイルの Write/Edit 後に品質ゲートを実行
#
# なぜ必要か:
#   moltbook で heartbeat.sh の修正ラリーが10分間で9コミット発生（2026-04-15）。
#   原因: local変数を関数外で使用、BSD mktemp非互換、pipefail未設定など。
#   shellcheck で機械的に検出できるバグを push 前にブロックする。
#
# 動作:
#   1. 編集ファイルが .sh でなければスキップ
#   2. shellcheck を実行（error レベルのみ）
#   3. launchd/cron で使うスクリプトは追加チェック
#   4. エラーがあれば additionalContext で AI に通知

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
    exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# .sh ファイルのみ対象
if [[ "$FILE_PATH" != *.sh ]]; then
    exit 0
fi

ISSUES=""

# --- Gate 1: shellcheck ---
if command -v shellcheck >/dev/null 2>&1; then
    # error レベルのみ（warning は多すぎてノイズになる）
    SC_OUTPUT=$(shellcheck -S error -f gcc "$FILE_PATH" 2>&1)
    if [ -n "$SC_OUTPUT" ]; then
        ISSUES="${ISSUES}## shellcheck errors\n${SC_OUTPUT}\n\n"
    fi
fi

# --- Gate 2: launchd/cron スクリプトの追加チェック ---
# plist から参照されているか、スクリプト内に launchd/cron の言及があるか
IS_LAUNCHD=false
if grep -ql "$FILE_PATH" ~/Library/LaunchAgents/*.plist 2>/dev/null; then
    IS_LAUNCHD=true
elif head -20 "$FILE_PATH" | grep -qi "launchd\|cron\|plist\|非対話\|non-interactive" 2>/dev/null; then
    IS_LAUNCHD=true
fi

if $IS_LAUNCHD; then
    # set -euo pipefail チェック
    if ! head -5 "$FILE_PATH" | grep -q 'set -.*e.*u.*o pipefail\|set -euo pipefail'; then
        ISSUES="${ISSUES}## launchd script missing safety flags\n"
        ISSUES="${ISSUES}\`set -euo pipefail\` がファイル先頭にありません。launchd で実行されるスクリプトには必須です。\n\n"
    fi

    # local 変数が関数外で使われていないかチェック
    # 関数定義の外にある local を検出（簡易的: 関数ブロック外の local）
    LOCAL_OUTSIDE=$(awk '
        /^[a-zA-Z_]+\s*\(\)\s*\{/ { in_func=1 }
        /^\}/ { if(in_func) in_func=0 }
        /^\s*local / { if(!in_func) print NR": "$0 }
    ' "$FILE_PATH")
    if [ -n "$LOCAL_OUTSIDE" ]; then
        ISSUES="${ISSUES}## local variable outside function\n"
        ISSUES="${ISSUES}以下の行で \`local\` が関数外で使われています（launchd の sh 互換モードで壊れます）:\n${LOCAL_OUTSIDE}\n\n"
    fi
fi

# --- 結果出力 ---
if [ -n "$ISSUES" ]; then
    echo "[shell-quality-gate] ${FILE_PATH} に問題があります。push前に修正してください。"
    echo ""
    echo -e "$ISSUES"
    # additionalContext として AI に渡す（ブロックはしない）
    echo "---"
    echo "修正後に再度 shellcheck を通してください: shellcheck -S error ${FILE_PATH}"
fi

exit 0
