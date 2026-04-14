#!/bin/bash
# budget/budget-consume.sh
#
# 目的:
#   LLM呼び出し完了後にoutput tokensを記録する。
#   logging-write.shへの薄いラッパー。
#
# 使用方法:
#   budget-consume.sh --tokens <output tokens> [--type <type>] [--label <label>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGGING_WRITE="$SCRIPT_DIR/../logging/logging-write.sh"

TOKENS=0
TYPE="unknown"
LABEL=""

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --tokens) shift; TOKENS="${1:-0}" ;;
    --type)   shift; TYPE="${1:-unknown}" ;;
    --label)  shift; LABEL="${1:-}" ;;
  esac
  shift
done

bash "$LOGGING_WRITE" \
  --type "$TYPE" \
  --status "done" \
  --output "$TOKENS" \
  --label "$LABEL"
