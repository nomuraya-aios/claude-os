#!/bin/bash
# kernel/hooks/pre-bash-no-verify-block.sh
#
# 目的:
#   git commit --no-verify など、hookをスキップするコマンドをブロックする。
#   セキュリティチェックのバイパスを防ぐ。
#   hook が失敗した場合は原因を調査・修正するよう促す。
#
# Claude Code hook type: PreToolUse (Bash)
# 入力: stdin から JSON {"tool_input": {"command": "..."}}

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

if echo "$COMMAND" | grep -qE 'git\s+.*--no-verify'; then
  echo '{"decision": "block", "reason": "--no-verify は禁止されています。hookが失敗した場合は原因を調査・修正してください。"}'
  exit 0
fi

echo '{"decision": "approve"}'
exit 0
