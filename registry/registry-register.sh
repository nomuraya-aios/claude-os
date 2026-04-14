#!/bin/bash
# registry/registry-register.sh
#
# 目的:
#   LLM呼び出しをレジストリに登録する。
#   process-runner・launchdジョブ・hookから呼ばれる。
#
# 使用方法:
#   registry-register.sh --type <type> --pid <pid> [--label <label>]
#
# type: session | job | issue | hook
# 出力: 発行したIDをstdoutに出力

set -euo pipefail

STATE_DIR="${AIOS_STATE_DIR:-$HOME/.local/share/claude-os/state}"
REGISTRY_FILE="$STATE_DIR/llm-registry.jsonl"

mkdir -p "$STATE_DIR"
touch "$REGISTRY_FILE"

TYPE=""
PID="${PPID}"
LABEL=""

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --type)  shift; TYPE="${1:-}" ;;
    --pid)   shift; PID="${1:-}" ;;
    --label) shift; LABEL="${1:-}" ;;
  esac
  shift
done

if [[ -z "$TYPE" ]]; then
  echo "使用方法: $0 --type <session|job|issue|hook> [--pid <pid>] [--label <label>]" >&2
  exit 1
fi

ID="$(date +%s%N)-$$"
STARTED_AT=$(TZ=UTC date '+%Y-%m-%dT%H:%M:%SZ')

ENTRY=$(jq -cn \
  --arg id "$ID" \
  --arg type "$TYPE" \
  --argjson pid "$PID" \
  --arg started_at "$STARTED_AT" \
  --arg label "$LABEL" \
  '{id: $id, type: $type, pid: $pid, started_at: $started_at, status: "running",
    input_tokens: 0, output_tokens: 0, total_tokens: 0, label: $label}')

LOCK="${REGISTRY_FILE}.lock"
while ! shlock -f "$LOCK" -p $$; do sleep 0.1; done
trap 'rm -f "$LOCK"' EXIT
echo "$ENTRY" >> "$REGISTRY_FILE"
rm -f "$LOCK"

echo "$ID"
