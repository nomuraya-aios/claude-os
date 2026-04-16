#!/usr/bin/env bash
# pre-bash-no-verify-block.sh
# Why: --no-verify bypasses pre-commit hooks, masking rule violations instead of fixing them.
# Hard-block at hook level so the prohibition cannot be ignored or missed.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# Match: git commit --no-verify, git commit -n, git commit -nXXX (combined flags)
if echo "$COMMAND" | grep -qE 'git\s+commit\s+.*(-n\b|--no-verify)'; then
  echo "❌ --no-verify / -n は禁止。pre-commit hookエラーが出る場合はhookのルール自体を修正すること。" >&2
  echo '{"decision": "block", "reason": "--no-verify は使用禁止（~/.claude/CLAUDE.md参照）"}'
  exit 0
fi
