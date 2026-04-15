#!/bin/bash
# meter/meter-baseline-update.sh
#
# 目的:
#   全セッションの cache_read 実測値から「新セッション開始時の基準値」を再計算して保存する。
#   月次 launchd から呼ばれる。LLM不使用。
#
# 出力: ~/.claude/state/new-session-baseline.json
#   {"baseline": N, "median": N, "p25": N, "p75": N, "sample_count": N, "updated_at": "..."}
#
# 基準値の定義:
#   cache_read 5M 未満のセッション（短い=新しいセッション相当）の中央値。
#   この値を fresh スキルが「新セッション起動コスト」として使う。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="$HOME/.claude/state/new-session-baseline.json"
THRESHOLD=5000000  # 5M tokens 未満を「短いセッション」と見なす

log() { echo "[$(TZ=Asia/Tokyo date '+%H:%M:%S')] $*" >&2; }

log "baseline 再計算開始"

# 全セッションをスキャンして cache_read を収集
VALUES=$(bash "$SCRIPT_DIR/meter-parse-session.sh" --all 2>/dev/null | \
  jq -r "select(.session_id | startswith(\"agent\") | not) | select(.cache_read < $THRESHOLD) | .cache_read" | \
  sort -n)

COUNT=$(echo "$VALUES" | grep -c '[0-9]' || echo 0)

if [[ "$COUNT" -lt 10 ]]; then
  log "サンプル数不足 ($COUNT 件) — baseline を更新しない"
  exit 0
fi

# 統計計算
MEDIAN=$(echo "$VALUES" | awk '{a[NR]=$1} END {print a[int(NR/2)]}')
P25=$(echo "$VALUES"   | awk '{a[NR]=$1} END {print a[int(NR*0.25)]}')
P75=$(echo "$VALUES"   | awk '{a[NR]=$1} END {print a[int(NR*0.75)]}')
UPDATED_AT=$(TZ=Asia/Tokyo date '+%Y-%m-%dT%H:%M:%S+09:00')

jq -n \
  --argjson baseline "$MEDIAN" \
  --argjson median "$MEDIAN" \
  --argjson p25 "$P25" \
  --argjson p75 "$P75" \
  --argjson count "$COUNT" \
  --arg updated_at "$UPDATED_AT" \
  '{baseline: $baseline, median: $median, p25: $p25, p75: $p75, sample_count: $count, updated_at: $updated_at}' \
  > "$OUTPUT"

log "baseline 更新完了: median=${MEDIAN} (${COUNT}件サンプル) → $OUTPUT"
cat "$OUTPUT"
