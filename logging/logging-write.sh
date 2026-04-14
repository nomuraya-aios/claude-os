#!/bin/bash
# logging/logging-write.sh
#
# 目的:
#   LLM呼び出しの結果を統一フォーマットでログに書き込む。
#   registry/meter/process-runnerから呼ばれる永続化層。
#
# 使用方法:
#   logging-write.sh --type <type> --status <status> \
#     [--input <n>] [--output <n>] [--cache-read <n>] \
#     [--duration <sec>] [--label <label>]

set -euo pipefail

LOG_DIR="${AIOS_LOG_DIR:-$HOME/.local/share/claude-os/logs}"
LOG_FILE="$LOG_DIR/llm-calls.jsonl"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

TYPE=""
STATUS=""
INPUT=0
OUTPUT=0
CACHE_READ=0
DURATION=0
LABEL=""

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --type)       shift; TYPE="${1:-}" ;;
    --status)     shift; STATUS="${1:-}" ;;
    --input)      shift; INPUT="${1:-0}" ;;
    --output)     shift; OUTPUT="${1:-0}" ;;
    --cache-read) shift; CACHE_READ="${1:-0}" ;;
    --duration)   shift; DURATION="${1:-0}" ;;
    --label)      shift; LABEL="${1:-}" ;;
  esac
  shift
done

if [[ -z "$TYPE" || -z "$STATUS" ]]; then
  echo "使用方法: $0 --type <type> --status <status> [options]" >&2
  exit 1
fi

TS=$(TZ=UTC date '+%Y-%m-%dT%H:%M:%SZ')
TOTAL=$((INPUT + CACHE_READ + OUTPUT))

ENTRY=$(jq -cn \
  --arg ts "$TS" \
  --arg type "$TYPE" \
  --argjson input "$INPUT" \
  --argjson cache_read "$CACHE_READ" \
  --argjson output "$OUTPUT" \
  --argjson total "$TOTAL" \
  --argjson duration "$DURATION" \
  --arg status "$STATUS" \
  --arg label "$LABEL" \
  '{ts: $ts, type: $type, input_tokens: $input, cache_read_tokens: $cache_read,
    output_tokens: $output, total_tokens: $total, duration_sec: $duration,
    status: $status, label: $label}')

LOCK="${LOG_FILE}.lock"
while ! shlock -f "$LOCK" -p $$; do sleep 0.1; done
trap 'rm -f "$LOCK"' EXIT
echo "$ENTRY" >> "$LOG_FILE"
rm -f "$LOCK"
