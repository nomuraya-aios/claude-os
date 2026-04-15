#!/bin/bash
# budget/budget-check.sh
#
# 目的:
#   LLM呼び出し実行前に残高を確認する。
#   上限超過時は exit 1 で呼び出し元をブロックする。
#   LLM不使用・数値比較のみ。
#
#   集計源: llm-calls.jsonl（Claude Code本体分は meter-bridge.sh で同期済み）
#   日付: JST基準（UTC+9）で当日を判定する
#
# 使用方法:
#   budget-check.sh --tokens <予想output tokens>
#   budget-check.sh --tokens 1000 --type job
#   budget-check.sh --sync   # 実行前に meter-bridge.sh を自動同期
#
# exit code:
#   0  正常（残高あり）
#   1  上限超過（呼び出し禁止）
#   2  設定ファイルなし（警告・通過）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${AIOS_CONFIG_DIR:-$SCRIPT_DIR/../config}/budget.yaml"
LOG_DIR="${AIOS_LOG_DIR:-$HOME/.local/share/claude-os/logs}"

TOKENS=0
TYPE="unknown"
SYNC=0

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --tokens) shift; TOKENS="${1:-0}" ;;
    --type)   shift; TYPE="${1:-unknown}" ;;
    --sync)   SYNC=1 ;;
  esac
  shift
done

# --sync: Claude Code セッションログを先に同期してから判定
if [[ "$SYNC" -eq 1 ]]; then
  BRIDGE="$SCRIPT_DIR/../meter/meter-bridge.sh"
  if [[ -f "$BRIDGE" ]]; then
    bash "$BRIDGE" 2>/dev/null || true
  fi
fi

# 設定ファイルがなければ警告のみで通過
if [[ ! -f "$CONFIG" ]]; then
  echo "[budget-check] WARN: 設定ファイルなし ($CONFIG) — スキップ" >&2
  exit 2
fi

# yamlから値を取得（LLM不使用・grepで抽出）
get_config() {
  grep "^${1}:" "$CONFIG" 2>/dev/null | awk '{print $2}' | tr -d ' '
}

PER_CALL=$(get_config "per_call")
DAILY=$(get_config "daily")

# 1呼び出し上限チェック
if [[ -n "$PER_CALL" && "$TOKENS" -gt "$PER_CALL" ]]; then
  echo "[budget-check] BLOCK: per_call上限超過 (${TOKENS} > ${PER_CALL})" >&2
  exit 1
fi

# 日次上限チェック（loggingから今日の消費量を取得）
# type="session" は Claude Code 本体の消費で budget の管轄外。
# バックグラウンド自動実行（job/hook/issue）のみを集計する。
if [[ -n "$DAILY" ]]; then
  USED_TODAY=0
  LOG_FILE="$LOG_DIR/llm-calls.jsonl"
  if [[ -f "$LOG_FILE" ]]; then
    # JST基準で当日を判定（UTC+9）
    TODAY=$(TZ=Asia/Tokyo date '+%Y-%m-%d')
    USED_TODAY=$( { grep "\"ts\":\"${TODAY}" "$LOG_FILE" 2>/dev/null || true; } \
      | { grep -v '"type":"session"' || true; } \
      | jq -r '.output_tokens // 0' \
      | awk '{s+=$1} END{print s+0}')
  fi

  REMAINING=$((DAILY - USED_TODAY))
  if [[ "$((USED_TODAY + TOKENS))" -gt "$DAILY" ]]; then
    echo "[budget-check] BLOCK: daily上限超過 (使用済み:${USED_TODAY} + 予定:${TOKENS} > 上限:${DAILY})" >&2
    exit 1
  fi

  echo "[budget-check] OK: daily残高 ${REMAINING} tokens (使用済み:${USED_TODAY}/${DAILY})" >&2
fi

exit 0
