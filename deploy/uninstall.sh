#!/bin/bash
# deploy/uninstall.sh
#
# 目的:
#   claude-os の完全削除・ロールバック。
#   aios CLI とサービス登録を削除する。
#   ソースディレクトリ自体は削除しない（git clone先はユーザーが管理）。
#
# 使用方法:
#   uninstall.sh [--all]
#   --all: 状態ディレクトリ（logs/state）も含めて削除

set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
STATE_DIR="${HOME}/.local/share/claude-os"

DO_ALL=0
mlog() { echo "[uninstall] $*"; }

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --all) DO_ALL=1 ;;
  esac
  shift
done

# --- aios CLI 削除 ---
if [[ -f "$BIN_DIR/aios" ]]; then
  mlog "aios CLI 削除: $BIN_DIR/aios"
  trash "$BIN_DIR/aios" 2>/dev/null || mv "$BIN_DIR/aios" ~/.Trash/ 2>/dev/null || rm "$BIN_DIR/aios"
  mlog "OK: aios 削除完了"
else
  mlog "aios CLI が見つかりません（スキップ）"
fi

# --- 状態ディレクトリ削除（--all のみ）---
if [[ "$DO_ALL" -eq 1 ]]; then
  if [[ -d "$STATE_DIR" ]]; then
    mlog "状態ディレクトリを削除: $STATE_DIR"
    mlog "WARN: ログ・バジェット履歴・ブレーカー状態がすべて削除されます"
    trash "$STATE_DIR" 2>/dev/null || mv "$STATE_DIR" ~/.Trash/ 2>/dev/null
    mlog "OK: 状態ディレクトリ削除完了"
  fi
fi

mlog "アンインストール完了"
mlog "ソースディレクトリは削除していません。必要であれば手動で削除してください。"
