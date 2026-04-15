#!/bin/bash
# breaker/breaker-check.sh
#
# 目的:
#   サーキットブレーカーの状態を確認する。
#   OPEN時はexit 2でLLM呼び出しをブロックする。
#   トリップ条件を自動判定し、条件を満たせばOPENに遷移する。
#   LLM不使用・数値比較のみ。
#
# 使用方法:
#   breaker-check.sh
#
# exit code:
#   0  CLOSED（正常・呼び出し許可）
#   2  OPEN（遮断中・呼び出し禁止）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="${AIOS_STATE_DIR:-$HOME/.local/share/claude-os/state}"
LOG_DIR="${AIOS_LOG_DIR:-$HOME/.local/share/claude-os/logs}"
CONFIG="${AIOS_CONFIG_DIR:-$SCRIPT_DIR/../config}/budget.yaml"
BREAKER_STATE="$STATE_DIR/breaker-state.json"

mkdir -p "$STATE_DIR"

# 設定読み込み
get_config() {
  [[ ! -f "$CONFIG" ]] && echo "" && return
  grep "^${1}:" "$CONFIG" 2>/dev/null | awk '{print $2}' | tr -d ' '
}

DAILY_LIMIT=$(get_config "daily")
THRESHOLD_PCT=$(get_config "breaker_threshold_pct")
THRESHOLD_PCT="${THRESHOLD_PCT:-80}"

# ブレーカー状態を読み込む（なければCLOSED）
read_state() {
  if [[ ! -f "$BREAKER_STATE" ]]; then
    echo "CLOSED"
    return
  fi
  jq -r '.state // "CLOSED"' "$BREAKER_STATE" 2>/dev/null || echo "CLOSED"
}

write_state() {
  local state="$1"
  local reason="${2:-}"
  local now
  now=$(TZ=UTC date '+%Y-%m-%dT%H:%M:%SZ')
  jq -cn \
    --arg state "$state" \
    --arg reason "$reason" \
    --arg updated_at "$now" \
    '{state: $state, reason: $reason, updated_at: $updated_at}' > "$BREAKER_STATE"
}

# 現在の状態確認
CURRENT_STATE=$(read_state)

if [[ "$CURRENT_STATE" == "OPEN" ]]; then
  REASON=$(jq -r '.reason // ""' "$BREAKER_STATE" 2>/dev/null)
  SINCE=$(jq -r '.updated_at // ""' "$BREAKER_STATE" 2>/dev/null)
  echo "[breaker] OPEN: 遮断中 (理由: $REASON / since: $SINCE)" >&2
  echo "[breaker] リセットするには: breaker-reset.sh" >&2
  exit 2
fi

# トリップ条件チェック（CLOSED時のみ）

# 条件: daily上限のTHRESHOLD_PCT%超過
if [[ -n "$DAILY_LIMIT" ]]; then
  # JST基準で当日を判定（UTC+9）
  TODAY=$(TZ=Asia/Tokyo date '+%Y-%m-%d')
  LOG_FILE="$LOG_DIR/llm-calls.jsonl"
  USED_TODAY=0
  # type="session" は Claude Code 本体の消費で breaker の管轄外。
  # バックグラウンド自動実行（job/hook/issue）のみをトリップ判定に使う。
  if [[ -f "$LOG_FILE" ]]; then
    USED_TODAY=$( { grep "\"ts\":\"${TODAY}" "$LOG_FILE" 2>/dev/null || true; } \
      | { grep -v '"type":"session"' || true; } \
      | jq -r '.output_tokens // 0' \
      | awk '{s+=$1} END{print s+0}')
  fi

  THRESHOLD=$((DAILY_LIMIT * THRESHOLD_PCT / 100))
  if [[ "$USED_TODAY" -gt "$THRESHOLD" ]]; then
    REASON="daily上限の${THRESHOLD_PCT}%超過 (${USED_TODAY}/${DAILY_LIMIT})"
    write_state "OPEN" "$REASON"
    echo "[breaker] TRIP: $REASON" >&2
    exit 2
  fi

  echo "[breaker] CLOSED: daily使用 ${USED_TODAY}/${DAILY_LIMIT} (閾値:${THRESHOLD})" >&2
fi

exit 0
