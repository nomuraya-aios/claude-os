#!/bin/bash
# breaker/breaker-trip.sh
#
# 目的:
#   サーキットブレーカーを手動でOPENにする。
#   異常検知時や緊急停止に使う。
#
# 使用方法:
#   breaker-trip.sh --reason "異常なトークン消費を検知"

set -euo pipefail

STATE_DIR="${AIOS_STATE_DIR:-$HOME/.local/share/claude-os/state}"
BREAKER_STATE="$STATE_DIR/breaker-state.json"

mkdir -p "$STATE_DIR"

REASON="${1:-手動トリップ}"
while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --reason) shift; REASON="${1:-手動トリップ}" ;;
  esac
  shift
done

NOW=$(TZ=UTC date '+%Y-%m-%dT%H:%M:%SZ')
jq -cn \
  --arg reason "$REASON" \
  --arg updated_at "$NOW" \
  '{state: "OPEN", reason: $reason, updated_at: $updated_at}' > "$BREAKER_STATE"

echo "[breaker] TRIPPED: $REASON"
echo "[breaker] 全LLM呼び出しをブロックします"
echo "[breaker] リセット: breaker-reset.sh"
