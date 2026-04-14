#!/bin/bash
# meter/meter-record.sh
#
# 目的:
#   LLM呼び出しのトークン消費をregistryに記録する。
#   process-runnerやoh-dispatchの出力から呼ばれる。
#
# 使用方法:
#   meter-record.sh --id <registry-id> --input <n> --output <n> [--cache-read <n>]
#   meter-record.sh --id <registry-id> --done   # ステータスをdoneに更新

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGISTRY_UPDATE="$SCRIPT_DIR/../registry/registry-update.sh"

ID=""
INPUT_TOKENS=""
OUTPUT_TOKENS=""
CACHE_READ_TOKENS=""
MARK_DONE=0

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --id)          shift; ID="${1:-}" ;;
    --input)       shift; INPUT_TOKENS="${1:-}" ;;
    --output)      shift; OUTPUT_TOKENS="${1:-}" ;;
    --cache-read)  shift; CACHE_READ_TOKENS="${1:-}" ;;
    --done)        MARK_DONE=1 ;;
  esac
  shift
done

if [[ -z "$ID" ]]; then
  echo "使用方法: $0 --id <registry-id> [--input <n>] [--output <n>] [--done]" >&2
  exit 1
fi

# registryに書き戻す
ARGS="--id $ID"
[[ -n "$INPUT_TOKENS" ]]      && ARGS="$ARGS --input $INPUT_TOKENS"
[[ -n "$OUTPUT_TOKENS" ]]     && ARGS="$ARGS --output $OUTPUT_TOKENS"
[[ "$MARK_DONE" -eq 1 ]]      && ARGS="$ARGS --status done"

bash "$REGISTRY_UPDATE" $ARGS
