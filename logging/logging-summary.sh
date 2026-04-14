#!/bin/bash
# logging/logging-summary.sh
#
# 目的:
#   llm-calls.jsonl を集計して日次・月次サマリを表示する。
#   budget/breakerへの数値供給にも使う。
#   LLM不使用・jq+awkのみ。
#
# 使用方法:
#   logging-summary.sh              # 今日
#   logging-summary.sh --date 2026-04-14
#   logging-summary.sh --month 2026-04
#   logging-summary.sh --output-tokens  # output_tokensのみ返す（budget用）

set -euo pipefail

LOG_DIR="${AIOS_LOG_DIR:-$HOME/.local/share/claude-os/logs}"
LOG_FILE="$LOG_DIR/llm-calls.jsonl"

MODE="today"
TARGET=""
OUTPUT_ONLY=0

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --date)          MODE="date";  shift; TARGET="${1:-}" ;;
    --month)         MODE="month"; shift; TARGET="${1:-}" ;;
    --all)           MODE="all" ;;
    --output-tokens) OUTPUT_ONLY=1 ;;
  esac
  shift
done

if [[ ! -f "$LOG_FILE" ]]; then
  [[ "$OUTPUT_ONLY" -eq 1 ]] && echo 0 || echo "ログなし（LLM呼び出し記録なし）"
  exit 0
fi

# 日付フィルタ（grep で高速絞り込み）
case "$MODE" in
  today) FILTER=$(TZ=UTC date '+%Y-%m-%d') ;;
  date)  FILTER="$TARGET" ;;
  month) FILTER="$TARGET" ;;
  all)   FILTER="" ;;
esac

if [[ -n "$FILTER" ]]; then
  LINES=$(grep "\"ts\":\"${FILTER}" "$LOG_FILE" 2>/dev/null || true)
else
  LINES=$(cat "$LOG_FILE")
fi

if [[ -z "$LINES" ]]; then
  [[ "$OUTPUT_ONLY" -eq 1 ]] && echo 0 || echo "データなし"
  exit 0
fi

# jqで一括集計（LLM不使用）
SUMMARY=$(echo "$LINES" | jq -sc '{
  count:       length,
  input:       ([.[].input_tokens       // 0] | add // 0),
  cache_read:  ([.[].cache_read_tokens  // 0] | add // 0),
  output:      ([.[].output_tokens      // 0] | add // 0),
  total:       ([.[].total_tokens       // 0] | add // 0),
  duration:    ([.[].duration_sec       // 0] | add // 0),
  done:        ([.[] | select(.status == "done")]   | length),
  failed:      ([.[] | select(.status == "failed")] | length)
}')

# --output-tokensモード（budget/breaker用の数値のみ返す）
if [[ "$OUTPUT_ONLY" -eq 1 ]]; then
  echo "$SUMMARY" | jq -r '.output'
  exit 0
fi

COUNT=$(echo "$SUMMARY"  | jq -r '.count')
INPUT=$(echo "$SUMMARY"  | jq -r '.input')
CACHE=$(echo "$SUMMARY"  | jq -r '.cache_read')
OUTPUT=$(echo "$SUMMARY" | jq -r '.output')
TOTAL=$(echo "$SUMMARY"  | jq -r '.total')
DONE=$(echo "$SUMMARY"   | jq -r '.done')
FAILED=$(echo "$SUMMARY" | jq -r '.failed')

case "$MODE" in
  today) LABEL="今日 ($(TZ=UTC date '+%Y-%m-%d') UTC)" ;;
  date)  LABEL="$TARGET" ;;
  month) LABEL="$TARGET" ;;
  all)   LABEL="全期間" ;;
esac

echo "=== LLM呼び出しログ サマリ: $LABEL ==="
echo ""
printf "  呼び出し数:       %d 件（完了:%d 失敗:%d）\n" "$COUNT" "$DONE" "$FAILED"
printf "  input tokens:     %d\n" "$INPUT"
printf "  cache_read:       %d\n" "$CACHE"
printf "  output tokens:    %d\n" "$OUTPUT"
printf "  合計:             %d\n" "$TOTAL"
echo ""

# type別内訳
echo "type別:"
echo "$LINES" | jq -r '.type' | sort | uniq -c | sort -rn | \
  while read -r cnt typ; do
    printf "  %-12s %d件\n" "$typ" "$cnt"
  done
