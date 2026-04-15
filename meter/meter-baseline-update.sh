#!/bin/bash
# meter/meter-baseline-update.sh
#
# 目的:
#   新規セッション起動直後の「初回 cache_read > 0」実測値を集計し、
#   「新セッション開始時の固定コスト」基準値を再計算して保存する。
#   月次 launchd から呼ばれる。LLM不使用。
#
# 出力: ~/.claude/state/new-session-baseline.json
#   {"baseline": N, "median": N, "p25": N, "p75": N, "sample_count": N, "updated_at": "..."}
#
# 基準値の定義:
#   各セッションの「初回 cache_read_input_tokens > 0」エントリの中央値。
#   CLAUDE.md + ルールファイル群の読み込みが完了した直後の値 = 毎回確定で生じるコスト。
#   agent セッション（CLAUDE.md を読まない）は除外済み。
#   この値を fresh スキルが「新セッション起動コスト」として使う。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="$HOME/.claude/state/new-session-baseline.json"

log() { echo "[$(TZ=Asia/Tokyo date '+%H:%M:%S')] $*" >&2; }

log "baseline 再計算開始（meter-parse-first-turn.sh 使用）"

# 初回 cr 実測値から統計を取得
STATS=$(bash "$SCRIPT_DIR/meter-parse-first-turn.sh" --stats 2>/dev/null || true)

COUNT=$(echo "$STATS" | jq -r '.count // 0')

if [[ "$COUNT" -lt 10 ]]; then
  log "サンプル数不足 ($COUNT 件) — baseline を更新しない"
  exit 0
fi

MEDIAN=$(echo "$STATS" | jq -r '.median')
P25=$(echo "$STATS"    | jq -r '.p25')
P75=$(echo "$STATS"    | jq -r '.p75')
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
