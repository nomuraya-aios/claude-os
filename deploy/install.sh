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
INSTALL_DIR="${CLAUDE_OS_INSTALL_DIR:-$HOME/.local/share/claude-os/repo}"
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

# --- kernel を ~/.claude/ にマージ ---
mlog "kernel ルール・hookを ~/.claude/ にマージ..."
if bash "$INSTALL_DIR/deploy/sync.sh" 2>&1; then
  mlog "OK: kernel マージ完了"
else
  mwarn "kernel マージをスキップしました（kernel/ が未整備の可能性）"
fi

# --- 全スキルをインストール（既存は保護）---
# 既存スキルは上書きしない。ユーザーが独自に持っているスキルは尊重する。
mlog ""
mlog "スキルをインストール中（既存は保護）..."
MANIFEST="$INSTALL_DIR/packages/manifest.yaml"
INSTALLED_SKILLS=()
PROTECTED_SKILLS=()
FAILED_SKILLS=()

if [[ -f "$MANIFEST" ]]; then
  SKILL_NAMES=$(grep -E '^  - name:' "$MANIFEST" | awk '{print $3}')
  for skill in $SKILL_NAMES; do
    OUTPUT=$(bash "$INSTALL_DIR/packages/packages-install.sh" "$skill" 2>&1)
    EXIT_CODE=$?
    if echo "$OUTPUT" | grep -q "スキップ（既存）"; then
      PROTECTED_SKILLS+=("$skill")
    elif [[ "$EXIT_CODE" -eq 0 ]]; then
      INSTALLED_SKILLS+=("$skill")
    else
      FAILED_SKILLS+=("$skill")
    fi
  done
else
  mwarn "manifest.yaml が見つかりません — スキルインストールをスキップ"
fi

# --- 完了メッセージ ---
mlog ""
mlog "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mlog " claude-os インストール完了!"
mlog "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mlog ""
mlog " インストール先: $INSTALL_DIR"
mlog " CLI:           $BIN_DIR/aios"
mlog ""

get_trigger() {
  local skill="$1"
  awk "
    /^  - name: ${skill}\$/ { found=1 }
    found && /^    trigger:/ { gsub(/^    trigger: */, \"\"); gsub(/^\"|\"$/, \"\"); print; exit }
    found && /^  - name:/ && !/^  - name: ${skill}\$/ { exit }
  " "$MANIFEST" 2>/dev/null || echo ""
}

if [[ "${#INSTALLED_SKILLS[@]}" -gt 0 ]]; then
  mlog " 新たに使えるスキル:"
  for skill in "${INSTALLED_SKILLS[@]}"; do
    trigger=$(get_trigger "$skill")
    [[ -n "$trigger" ]] && mlog "   • $trigger" || mlog "   • $skill"
  done
  mlog ""
fi

if [[ "${#PROTECTED_SKILLS[@]}" -gt 0 ]]; then
  mlog " 保護（既存を維持）: ${PROTECTED_SKILLS[*]}"
  mlog " → 上書きするには: aios install <name> --force"
  mlog ""
fi

if [[ "${#FAILED_SKILLS[@]}" -gt 0 ]]; then
  mlog " スキップ（依存ツール不足）: ${FAILED_SKILLS[*]}"
  mlog " → 依存ツールを入れてから: aios install <name>"
  mlog ""
fi

mlog " Claude Code を再起動するとスキルが有効になります"
mlog ""
mlog " その他のコマンド:"
mlog "   aios health           # ヘルスチェック"
mlog "   aios list --installed  # インストール済みスキル一覧"
