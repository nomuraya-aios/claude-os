#!/bin/bash
# kernel/hooks/pre-bash-rm-rf-block.sh
#
# 目的:
#   rm -rf を含む bash コマンドを事前にブロックする。
#   git管理外ファイルの永久消失事故を防ぐ。
#
# Claude Code hook type: PreToolUse (Bash)
# 入力: stdin から JSON {"tool_input": {"command": "..."}}

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

if echo "$COMMAND" | grep -qE 'rm\s+-[a-zA-Z]*r[a-zA-Z]*f|rm\s+-[a-zA-Z]*f[a-zA-Z]*r'; then
  echo '{"decision": "block", "reason": "rm -rf は禁止されています。trash コマンドまたは mv ~/.Trash/ を使用してください。"}'
  exit 0
fi

echo '{"decision": "approve"}'
exit 0
