#!/bin/bash
# deploy/uninstall.sh
#
# 目的:
#   claude-os がインストールしたものだけを削除する。
#   ユーザーが自分で作った設定・スキルは一切触らない。
#   インストーラーと対称な設計: 入れたものだけ消す。
#
# 削除対象:
#   - ~/.local/bin/aios               (aios CLI)
#   - ~/.claude/skills/<name>          (manifest.yaml に定義されたスキルのみ)
#   - ~/.claude/rules/<file>           (kernel/rules/ にある同名ファイルのみ)
#   - ~/.claude/hooks/<file>           (kernel/hooks/ にある同名ファイルのみ)
#   - ~/.claude/CLAUDE.md の claude-os トリガー行
#   - ~/.local/share/claude-os/        (--all 指定時のみ)
#
# 使用方法:
#   uninstall.sh [--all] [--dry-run]
#   --all:     状態ディレクトリ（logs/state）も削除
#   --dry-run: 削除せず対象を表示のみ

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AIOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$AIOS_ROOT/packages/manifest.yaml"
KERNEL_RULES="$AIOS_ROOT/kernel/rules"
KERNEL_HOOKS="$AIOS_ROOT/kernel/hooks"
BIN_DIR="${HOME}/.local/bin"
CLAUDE_DIR="${HOME}/.claude"
STATE_DIR="${HOME}/.local/share/claude-os"

DO_ALL=0
DRY_RUN=0
REMOVED=0

mlog()  { echo "[uninstall] $*"; }
mwarn() { echo "[uninstall] WARN: $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --all)     DO_ALL=1 ;;
    --dry-run) DRY_RUN=1 ;;
  esac
  shift
done

# ファイル/ディレクトリを安全に削除（trash → ~/.Trash → rm の順で試みる）
safe_remove() {
  local target="$1"
  local label="${2:-$target}"
  if [[ ! -e "$target" ]]; then
    mlog "  SKIP (存在しない): $label"
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    mlog "  REMOVE (dry-run): $label"
  else
    trash "$target" 2>/dev/null \
      || mv "$target" ~/.Trash/ 2>/dev/null \
      || { [[ -f "$target" ]] && rm "$target"; }
    mlog "  REMOVED: $label"
  fi
  REMOVED=$((REMOVED + 1))
}

# --- aios CLI ---
mlog "aios CLI を削除..."
safe_remove "$BIN_DIR/aios" "~/.local/bin/aios"

# --- スキル（manifest.yaml の install_dest のみ）---
mlog ""
mlog "スキルを削除（claude-os インストール分のみ）..."
if [[ -f "$MANIFEST" ]]; then
  while IFS= read -r skill_name; do
    [[ -z "$skill_name" ]] && continue
    install_dest=$(awk -v pkg="$skill_name" '
      /^  - name:/ { in_block = ($NF == pkg) }
      in_block && /^    install_dest:/ {
        val = $0; sub(/^[^:]*: */, "", val); gsub(/^"|"$/, "", val); print val; exit
      }
    ' "$MANIFEST")
    install_dest="${install_dest/#\~/$HOME}"
    [[ -z "$install_dest" ]] && continue
    safe_remove "$install_dest" "~/.claude/skills/$skill_name"
  done < <(grep -E '^  - name:' "$MANIFEST" | awk '{print $3}')
else
  mwarn "manifest.yaml が見つかりません — スキル削除をスキップ"
fi

# --- kernel 由来の rules ---
mlog ""
mlog "kernel rules を削除..."
if [[ -d "$KERNEL_RULES" ]]; then
  while IFS= read -r -d '' src_file; do
    [[ "$(basename "$src_file")" == ".gitkeep" ]] && continue
    rel="${src_file#$KERNEL_RULES/}"
    safe_remove "$CLAUDE_DIR/rules/$rel" "~/.claude/rules/$rel"
  done < <(find "$KERNEL_RULES" -type f -print0)
else
  mwarn "kernel/rules/ が見つかりません — rules 削除をスキップ"
fi

# --- kernel 由来の hooks ---
mlog ""
mlog "kernel hooks を削除..."
if [[ -d "$KERNEL_HOOKS" ]]; then
  while IFS= read -r -d '' src_file; do
    [[ "$(basename "$src_file")" == ".gitkeep" ]] && continue
    rel="${src_file#$KERNEL_HOOKS/}"
    safe_remove "$CLAUDE_DIR/hooks/$rel" "~/.claude/hooks/$rel"
  done < <(find "$KERNEL_HOOKS" -type f -print0)
else
  mwarn "kernel/hooks/ が見つかりません — hooks 削除をスキップ"
fi

# --- CLAUDE.md のトリガー行 ---
mlog ""
mlog "CLAUDE.md のトリガー行を削除..."
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]]; then
  if grep -q "claude-os-skill:\|<!-- claude-os skills -->" "$CLAUDE_MD" 2>/dev/null; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      mlog "  REMOVE (dry-run): claude-os トリガー行"
      grep -n "claude-os-skill:\|<!-- claude-os skills -->" "$CLAUDE_MD" | while IFS= read -r line; do
        mlog "    $line"
      done
    else
      # claude-os マーカー行とトリガー行をすべて削除
      sed -i '' '/<!-- claude-os skills -->/d' "$CLAUDE_MD"
      sed -i '' '/<!-- claude-os-skill:/d' "$CLAUDE_MD"
      mlog "  REMOVED: claude-os トリガー行"
    fi
    REMOVED=$((REMOVED + 1))
  else
    mlog "  SKIP (トリガー行なし)"
  fi
else
  mlog "  SKIP (CLAUDE.md が見つかりません)"
fi

# --- 状態ディレクトリ（--all のみ）---
if [[ "$DO_ALL" -eq 1 ]]; then
  mlog ""
  mlog "状態ディレクトリを削除..."
  safe_remove "$STATE_DIR" "~/.local/share/claude-os/"
fi

# --- 完了 ---
mlog ""
mlog "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mlog " アンインストール完了: ${REMOVED} 件削除"
[[ "$DRY_RUN" -eq 1 ]] && mlog " (dry-run のため実際の変更はありません)"
mlog "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mlog ""
mlog " ソースディレクトリは削除していません:"
mlog "   $AIOS_ROOT"
mlog " 不要であれば手動で削除してください"
