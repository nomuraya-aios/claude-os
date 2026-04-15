#!/bin/bash
# meter/meter-bridge.sh
#
# 目的:
#   Claude Code本体のセッションログ（~/.claude/projects/**/*.jsonl）を
#   llm-calls.jsonl に同期する。
#   これにより budget-check.sh と breaker-check.sh が Claude Code の
#   トークン消費を正しく認識できるようになる。
#
#   meter-parse-session.sh が「読む側」、このスクリプトが「書く側」。
#   重複書き込みを防ぐため processed-sessions.txt で済み記録を管理する。
#
# 使用方法:
#   meter-bridge.sh              # 今日分を同期
#   meter-bridge.sh --date 2026-04-14
#   meter-bridge.sh --force      # 済み記録を無視して再同期（デバッグ用）
#
# LLM不使用・jq+awkのみ。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${AIOS_LOG_DIR:-$HOME/.local/share/claude-os/logs}"
STATE_DIR="${AIOS_STATE_DIR:-$HOME/.local/share/claude-os/state}"
PARSE="$SCRIPT_DIR/meter-parse-session.sh"

LOG_FILE="$LOG_DIR/llm-calls.jsonl"
PROCESSED="$STATE_DIR/meter-bridge-processed.txt"

mkdir -p "$LOG_DIR" "$STATE_DIR"
touch "$LOG_FILE" "$PROCESSED"

TARGET_DATE=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --date)  shift; TARGET_DATE="${1:-}" ;;
    --force) FORCE=1 ;;
  esac
  shift
done

# パーサー呼び出し
if [[ -n "$TARGET_DATE" ]]; then
  LINES=$(bash "$PARSE" --date "$TARGET_DATE")
else
  LINES=$(bash "$PARSE")
fi

if [[ -z "$LINES" ]]; then
  echo "[meter-bridge] 同期対象なし" >&2
  exit 0
fi

SYNCED=0
SKIPPED=0

LOCK="${LOG_FILE}.lock"
# shlock がなければ flock で代替
if command -v shlock &>/dev/null; then
  while ! shlock -f "$LOCK" -p $$; do sleep 0.1; done
  trap 'rm -f "$LOCK"' EXIT
else
  exec 200>"$LOCK"
  flock -x 200
  trap 'rm -f "$LOCK"' EXIT
fi

while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  SESSION_ID=$(echo "$line" | jq -r '.session_id // ""')
  [[ -z "$SESSION_ID" ]] && continue

  # 済みチェック（--force 時はスキップ）
  if [[ "$FORCE" -eq 0 ]] && grep -qx "$SESSION_ID" "$PROCESSED" 2>/dev/null; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # llm-calls.jsonl のフォーマットに変換して追記
  DATE=$(echo "$line" | jq -r '.date // ""')
  INPUT=$(echo "$line" | jq -r '.input // 0')
  CACHE_READ=$(echo "$line" | jq -r '.cache_read // 0')
  OUTPUT=$(echo "$line" | jq -r '.output // 0')
  TOTAL=$(echo "$line" | jq -r '.total // 0')

  # ts は JST 日付を保持する形式にする
  # budget-check.sh が "ts":"YYYY-MM-DD" の JST 日付で grep するため、
  # ts フィールドは JST 日付プレフィックスを持つ文字列にする
  TS="${DATE}T00:00:00+09:00"

  ENTRY=$(jq -cn \
    --arg ts "$TS" \
    --arg type "session" \
    --argjson input "$INPUT" \
    --argjson cache_read "$CACHE_READ" \
    --argjson output "$OUTPUT" \
    --argjson total "$TOTAL" \
    --arg label "claude-code:$SESSION_ID" \
    '{ts: $ts, type: $type,
      input_tokens: $input, cache_read_tokens: $cache_read,
      output_tokens: $output, total_tokens: $total,
      duration_sec: 0, status: "done", label: $label}')

  echo "$ENTRY" >> "$LOG_FILE"
  echo "$SESSION_ID" >> "$PROCESSED"
  SYNCED=$((SYNCED + 1))

done <<< "$LINES"

echo "[meter-bridge] 同期完了: ${SYNCED}件追記 / ${SKIPPED}件スキップ（済み）" >&2
