#!/bin/bash
# meter/meter-summary.sh
#
# 目的:
#   meter-parse-session.sh の出力を集計して人間向けサマリを表示する。
#   LLM不使用・awk+jqのみ。
#
# 使用方法:
#   meter-summary.sh              # 今日
#   meter-summary.sh --date 2026-04-14
#   meter-summary.sh --month 2026-04
#   meter-summary.sh --all

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSE="$SCRIPT_DIR/meter-parse-session.sh"

MODE="today"
TARGET=""

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --date)  MODE="date";  shift; TARGET="${1:-}" ;;
    --month) MODE="month"; shift; TARGET="${1:-}" ;;
    --all)   MODE="all" ;;
  esac
  shift
done

# パーサー呼び出し
case "$MODE" in
  today) LINES=$(bash "$PARSE") ;;
  date)  LINES=$(bash "$PARSE" --date "$TARGET") ;;
  month) LINES=$(bash "$PARSE" --all | grep "\"date\":\"${TARGET}") ;;
  all)   LINES=$(bash "$PARSE" --all) ;;
esac

if [[ -z "$LINES" ]]; then
  echo "データなし"
  exit 0
fi

# 集計（jqで一括）
SUMMARY=$(echo "$LINES" | jq -sc '
  {
    sessions:   length,
    input:      ([.[].input // 0]      | add // 0),
    cache_read: ([.[].cache_read // 0] | add // 0),
    output:     ([.[].output // 0]     | add // 0),
    total:      ([.[].total // 0]      | add // 0)
  }
')

SESSIONS=$(echo "$SUMMARY" | jq -r '.sessions')
INPUT=$(echo "$SUMMARY" | jq -r '.input')
CACHE_READ=$(echo "$SUMMARY" | jq -r '.cache_read')
OUTPUT=$(echo "$SUMMARY" | jq -r '.output')
TOTAL=$(echo "$SUMMARY" | jq -r '.total')

case "$MODE" in
  today) LABEL="今日 ($(TZ=Asia/Tokyo date '+%Y-%m-%d'))" ;;
  date)  LABEL="$TARGET" ;;
  month) LABEL="$TARGET" ;;
  all)   LABEL="全期間" ;;
esac

echo "=== トークン消費サマリ: $LABEL ==="
echo ""
printf "  セッション数:     %d 件\n" "$SESSIONS"
printf "  input tokens:     %'d\n" "$INPUT"
printf "  cache_read:       %'d\n" "$CACHE_READ"
printf "  output tokens:    %'d\n" "$OUTPUT"
printf "  合計:             %'d\n" "$TOTAL"
echo ""

# 上位セッション（total降順 top5）
echo "上位5セッション:"
echo "$LINES" | jq -r '[.session_id, (.total|tostring)] | join("\t")' 2>/dev/null \
  | sort -t$'\t' -k2 -rn | head -5 \
  | while IFS=$'\t' read -r sid tok; do
      printf "  %-40s %'d tokens\n" "${sid:0:36}..." "$tok"
    done
