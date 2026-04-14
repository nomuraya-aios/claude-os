#!/bin/bash
# registry/registry-update.sh
#
# 目的:
#   レジストリのエントリを更新する（トークン数・ステータス）。
#   meterからトークン数を受け取り書き戻す。
#
# 使用方法:
#   registry-update.sh --id <id> [--input <n>] [--output <n>] [--status <s>]

set -euo pipefail

STATE_DIR="${AIOS_STATE_DIR:-$HOME/.local/share/claude-os/state}"
REGISTRY_FILE="$STATE_DIR/llm-registry.jsonl"

ID=""
INPUT_TOKENS=""
OUTPUT_TOKENS=""
STATUS=""

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --id)     shift; ID="${1:-}" ;;
    --input)  shift; INPUT_TOKENS="${1:-}" ;;
    --output) shift; OUTPUT_TOKENS="${1:-}" ;;
    --status) shift; STATUS="${1:-}" ;;
  esac
  shift
done

if [[ -z "$ID" ]]; then
  echo "使用方法: $0 --id <id> [--input <n>] [--output <n>] [--status <s>]" >&2
  exit 1
fi

[[ ! -f "$REGISTRY_FILE" ]] && { echo "レジストリが存在しません" >&2; exit 1; }

NOW=$(TZ=UTC date '+%Y-%m-%dT%H:%M:%SZ')
TMP="${REGISTRY_FILE}.tmp.$$"

LOCK="${REGISTRY_FILE}.lock"
while ! shlock -f "$LOCK" -p $$; do sleep 0.1; done
trap 'rm -f "$LOCK"' EXIT

while IFS= read -r line; do
  LINE_ID=$(echo "$line" | jq -r '.id // ""')
  if [[ "$LINE_ID" == "$ID" ]]; then
    if [[ -n "$INPUT_TOKENS" ]]; then
      line=$(echo "$line" | jq -c \
        --argjson n "$INPUT_TOKENS" \
        '.input_tokens += $n | .total_tokens += $n')
    fi
    if [[ -n "$OUTPUT_TOKENS" ]]; then
      line=$(echo "$line" | jq -c \
        --argjson n "$OUTPUT_TOKENS" \
        '.output_tokens += $n | .total_tokens += $n')
    fi
    if [[ -n "$STATUS" ]]; then
      line=$(echo "$line" | jq -c \
        --arg s "$STATUS" --arg t "$NOW" \
        '. + {status: $s, updated_at: $t}')
      if [[ "$STATUS" == "done" || "$STATUS" == "failed" || "$STATUS" == "timeout" ]]; then
        line=$(echo "$line" | jq -c --arg t "$NOW" '. + {ended_at: $t}')
      fi
    fi
  fi
  echo "$line"
done < "$REGISTRY_FILE" > "$TMP"
mv "$TMP" "$REGISTRY_FILE"
rm -f "$LOCK"
