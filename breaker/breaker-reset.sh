#!/bin/bash
# breaker/breaker-reset.sh
#
# 目的:
#   サーキットブレーカーをCLOSEDに戻す。
#   人間が状況を確認してから手動で実行する（自動リセット禁止）。
#
# 使用方法:
#   breaker-reset.sh

set -euo pipefail

STATE_DIR="${AIOS_STATE_DIR:-$HOME/.local/share/claude-os/state}"
BREAKER_STATE="$STATE_DIR/breaker-state.json"

if [[ ! -f "$BREAKER_STATE" ]]; then
  echo "[breaker] 既にCLOSED（状態ファイルなし）"
  exit 0
fi

PREV_STATE=$(jq -r '.state // "CLOSED"' "$BREAKER_STATE" 2>/dev/null)
PREV_REASON=$(jq -r '.reason // ""' "$BREAKER_STATE" 2>/dev/null)

NOW=$(TZ=UTC date '+%Y-%m-%dT%H:%M:%SZ')
jq -cn \
  --arg updated_at "$NOW" \
  --arg prev_reason "$PREV_REASON" \
  '{state: "CLOSED", reason: "", updated_at: $updated_at, reset_from: $prev_reason}' \
  > "$BREAKER_STATE"

echo "[breaker] RESET: CLOSED に戻しました"
echo "[breaker] 前回トリップ理由: $PREV_REASON"
