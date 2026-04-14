#!/bin/bash
# health/health-check.sh
#
# 目的:
#   Claude Code 環境全体の健全性を確認する。
#   必須ツール・設定ファイル・ブレーカー状態・STATE_DIR書き込み権限を
#   一括チェックし、問題を早期に検出する。LLM不使用・bash + grep のみ。
#
# 使用方法:
#   health-check.sh
#
# exit code:
#   0  全OK
#   1  WARNあり（ブロックしない）
#   2  ERRあり（要対処）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="${AIOS_STATE_DIR:-$HOME/.local/share/claude-os/state}"

ok_count=0
warn_count=0
err_count=0

report_ok() {
  echo "[health] OK  : $1"
  ok_count=$((ok_count + 1))
}

report_warn() {
  echo "[health] WARN: $1"
  warn_count=$((warn_count + 1))
}

report_err() {
  echo "[health] ERR : $1"
  err_count=$((err_count + 1))
}

# 1. 必須ツール存在確認
for tool in gh git jq uv; do
  if command -v "$tool" &>/dev/null; then
    report_ok "必須ツール '$tool' が存在する"
  else
    report_err "必須ツール '$tool' が見つからない"
  fi
done

# 2. 推奨ツール存在確認（なければWARN、ブロックしない）
for tool in ndlocr-lite shlock oh-dispatch; do
  if command -v "$tool" &>/dev/null; then
    report_ok "推奨ツール '$tool' が存在する"
  else
    report_warn "推奨ツール '$tool' が見つからない（任意）"
  fi
done

# 3. ~/.claude/settings.json 存在確認
if [[ -f "$HOME/.claude/settings.json" ]]; then
  report_ok "~/.claude/settings.json が存在する"
else
  report_err "~/.claude/settings.json が見つからない"
fi

# 4. ~/.claude/hooks/ ディレクトリ存在確認
if [[ -d "$HOME/.claude/hooks" ]]; then
  report_ok "~/.claude/hooks/ ディレクトリが存在する"
else
  report_err "~/.claude/hooks/ ディレクトリが見つからない"
fi

# 5. budget 残高確認（breaker-check.sh の終了コードで判定）
BREAKER_SCRIPT="$SCRIPT_DIR/../breaker/breaker-check.sh"
if [[ ! -f "$BREAKER_SCRIPT" ]]; then
  report_warn "breaker-check.sh が見つからない（budget確認スキップ）"
else
  if bash "$BREAKER_SCRIPT" &>/dev/null; then
    report_ok "budget残高: CLOSED（呼び出し許可）"
  else
    exit_code=$?
    if [[ "$exit_code" -eq 2 ]]; then
      report_err "budget残高: ブレーカーOPEN（呼び出し遮断中）"
    else
      report_warn "budget残高: breaker-check.sh が予期しない終了コード ($exit_code)"
    fi
  fi
fi

# 6. STATE_DIR 書き込み権限確認
mkdir -p "$STATE_DIR" 2>/dev/null || true
if [[ -d "$STATE_DIR" ]] && [[ -w "$STATE_DIR" ]]; then
  report_ok "STATE_DIR '$STATE_DIR' への書き込み権限あり"
else
  report_err "STATE_DIR '$STATE_DIR' への書き込み権限なし（mkdir失敗またはパーミッション不足）"
fi

# 集計
echo "[health] 結果: OK=${ok_count} / WARN=${warn_count} / ERR=${err_count}"

if [[ "$err_count" -gt 0 ]]; then
  exit 2
elif [[ "$warn_count" -gt 0 ]]; then
  exit 1
fi

exit 0
