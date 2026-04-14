#!/bin/bash
# registry/registry-list.sh
#
# 目的:
#   レジストリの一覧を表示する。
#   デフォルトはrunning中のみ。--all で全件表示。
#
# 使用方法:
#   registry-list.sh              # running中のみ
#   registry-list.sh --all        # 全件
#   registry-list.sh --json       # JSON出力（スクリプト連携用）

set -euo pipefail

STATE_DIR="${AIOS_STATE_DIR:-$HOME/.local/share/claude-os/state}"
REGISTRY_FILE="$STATE_DIR/llm-registry.jsonl"

SHOW_ALL=0
JSON_OUTPUT=0

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --all)  SHOW_ALL=1 ;;
    --json) JSON_OUTPUT=1 ;;
  esac
  shift
done

if [[ ! -f "$REGISTRY_FILE" ]]; then
  [[ "$JSON_OUTPUT" -eq 0 ]] && echo "レジストリが存在しません（LLM呼び出しなし）"
  exit 0
fi

# フィルタリング（LLM不使用・grepのみ）
if [[ "$SHOW_ALL" -eq 1 ]]; then
  ENTRIES=$(cat "$REGISTRY_FILE")
else
  ENTRIES=$(grep '"status":"running"' "$REGISTRY_FILE" 2>/dev/null || true)
fi

if [[ -z "$ENTRIES" ]]; then
  [[ "$JSON_OUTPUT" -eq 0 ]] && echo "実行中のLLM呼び出しなし"
  exit 0
fi

if [[ "$JSON_OUTPUT" -eq 1 ]]; then
  echo "$ENTRIES"
  exit 0
fi

# 人間向け表示
echo "=== LLM呼び出しレジストリ ==="
echo ""
printf "%-28s %-10s %-8s %-10s %-10s %s\n" "ID（末尾8桁）" "TYPE" "STATUS" "TOKENS" "PID" "STARTED"
echo "$(printf '%0.s-' {1..80})"

echo "$ENTRIES" | while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  ID=$(echo "$line" | jq -r '.id // ""' | tail -c 9)
  TYPE=$(echo "$line" | jq -r '.type // ""')
  STATUS=$(echo "$line" | jq -r '.status // ""')
  TOTAL=$(echo "$line" | jq -r '.total_tokens // 0')
  PID=$(echo "$line" | jq -r '.pid // ""')
  STARTED=$(echo "$line" | jq -r '.started_at // ""' | cut -c1-19)
  LABEL=$(echo "$line" | jq -r '.label // ""')

  printf "%-28s %-10s %-8s %-10s %-10s %s\n" \
    "...${ID}" "$TYPE" "$STATUS" "$TOTAL" "$PID" "$STARTED"
  [[ -n "$LABEL" ]] && echo "  └ $LABEL"
done

echo ""
TOTAL_TOKENS=$(echo "$ENTRIES" | jq -r '.total_tokens // 0' | awk '{s+=$1} END {print s+0}')
COUNT=$(echo "$ENTRIES" | grep -c '"id"' || true)
echo "合計: ${COUNT}件 / ${TOTAL_TOKENS} tokens"
