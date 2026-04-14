#!/bin/bash
# deploy/install.sh
#
# 目的:
#   新規マシンへの claude-os ワンコマンドセットアップ。
#   curl -fsSL .../install.sh | bash で実行されることを想定。
#   依存ツールのチェックと ~/.claude/ への初期ファイル配置を行う。
#
# 使用方法:
#   bash install.sh [--repo <owner/repo>] [--branch <branch>]

set -euo pipefail

REPO="${CLAUDE_OS_REPO:-nomuraya-aios/claude-os}"
BRANCH="${CLAUDE_OS_BRANCH:-main}"
INSTALL_DIR="${CLAUDE_OS_INSTALL_DIR:-$HOME/workspace-ai/nomuraya-aios/claude-os}"
BIN_DIR="${HOME}/.local/bin"

mlog() { echo "[install] $*"; }
mwarn() { echo "[install] WARN: $*" >&2; }
merr() { echo "[install] ERR: $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --repo)   shift; REPO="${1:-$REPO}" ;;
    --branch) shift; BRANCH="${1:-$BRANCH}" ;;
    --dir)    shift; INSTALL_DIR="${1:-$INSTALL_DIR}" ;;
  esac
  shift
done

# --- 必須ツール確認 ---
mlog "必須ツール確認..."
MISSING=0
for cmd in git gh jq; do
  if ! command -v "$cmd" &>/dev/null; then
    merr "必須ツールが見つかりません: $cmd"
    MISSING=$((MISSING + 1))
  else
    mlog "OK: $cmd"
  fi
done

if [[ "$MISSING" -gt 0 ]]; then
  merr "必須ツールが不足しています。インストール後に再実行してください。"
  exit 1
fi

# --- リポジトリクローン or 更新 ---
if [[ -d "$INSTALL_DIR/.git" ]]; then
  mlog "既存インストールを更新: $INSTALL_DIR"
  git -C "$INSTALL_DIR" pull origin "$BRANCH"
else
  mlog "クローン: https://github.com/$REPO -> $INSTALL_DIR"
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone --branch "$BRANCH" "https://github.com/$REPO.git" "$INSTALL_DIR"
fi

# --- aios CLI インストール ---
mlog "aios CLI をインストール: $BIN_DIR/aios"
mkdir -p "$BIN_DIR"
cp "$INSTALL_DIR/bin/aios" "$BIN_DIR/aios"
chmod +x "$BIN_DIR/aios"

# PATH確認
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
  mwarn "$BIN_DIR が PATH に含まれていません。~/.zshrc or ~/.bashrc に追加してください:"
  mwarn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# --- 状態ディレクトリ作成 ---
STATE_DIR="${HOME}/.local/share/claude-os/state"
LOG_DIR="${HOME}/.local/share/claude-os/logs"
mkdir -p "$STATE_DIR" "$LOG_DIR"
mlog "状態ディレクトリ作成: $STATE_DIR"

# --- 完了 ---
mlog ""
mlog "インストール完了!"
mlog "  インストール先: $INSTALL_DIR"
mlog "  CLI:           $BIN_DIR/aios"
mlog ""
mlog "次のステップ:"
mlog "  aios health    # ヘルスチェック"
mlog "  aios list      # パッケージ一覧"
