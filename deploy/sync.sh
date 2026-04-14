#!/bin/bash
# deploy/sync.sh
#
# 目的:
#   kernel/ の変更を ~/.claude/ に反映する。
#   kernel移管完了後（#1完了後）に本格稼働予定。
#   現時点では: kernel/ が空のため、~/.claude/rules/と~/.claude/hooks/の
#   差分確認のみ行い、実際のrsyncはdry-runモードで表示する。
#
# 使用方法:
#   sync.sh [--dry-run] [--backup]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AIOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL_DIR="$AIOS_ROOT/kernel"
CLAUDE_DIR="${HOME}/.claude"
BACKUP_DIR="${HOME}/.local/share/claude-os/backups/$(TZ=UTC date '+%Y%m%dT%H%M%SZ')"

DRY_RUN=0
DO_BACKUP=0

mlog() { echo "[sync] $*"; }

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --dry-run) DRY_RUN=1 ;;
    --backup)  DO_BACKUP=1 ;;
  esac
  shift
done

# --- kernel/ にコンテンツがあるか確認 ---
KERNEL_RULES="$KERNEL_DIR/rules"
KERNEL_HOOKS="$KERNEL_DIR/hooks"

if [[ ! -d "$KERNEL_RULES" ]] && [[ ! -d "$KERNEL_HOOKS" ]]; then
  mlog "WARN: kernel/rules/ および kernel/hooks/ が存在しません。"
  mlog "      #1 (kernel移管) 完了後に再実行してください。"
  mlog ""
  mlog "現在の ~/.claude/ 状態:"
  [[ -d "$CLAUDE_DIR/rules" ]] && mlog "  rules/: $(ls "$CLAUDE_DIR/rules/" 2>/dev/null | wc -l | tr -d ' ') ファイル" || mlog "  rules/: なし"
  [[ -d "$CLAUDE_DIR/hooks" ]] && mlog "  hooks/: $(ls "$CLAUDE_DIR/hooks/" 2>/dev/null | wc -l | tr -d ' ') ファイル" || mlog "  hooks/: なし"
  exit 0
fi

# --- kernel が .gitkeep のみ（空）なら安全ブロック ---
# kernel/rules/ または kernel/hooks/ が実質空（.gitkeep のみ）の場合、
# --delete オプションが ~/.claude/ の既存ファイルを全消しするため実行を拒否する
check_kernel_not_empty() {
  local dir="$1"
  [[ ! -d "$dir" ]] && return 0
  local count
  count=$(find "$dir" -type f ! -name ".gitkeep" | wc -l | tr -d ' ')
  if [[ "$count" -eq 0 ]]; then
    merr "kernel/ が空です（.gitkeepのみ）。同期すると ~/.claude/ のファイルが削除されます。"
    merr "kernel移管(#1)完了後に再実行してください。"
    exit 1
  fi
}
merr() { echo "[sync] ERR: $*" >&2; }
check_kernel_not_empty "$KERNEL_RULES"
check_kernel_not_empty "$KERNEL_HOOKS"

# --- バックアップ ---
if [[ "$DO_BACKUP" -eq 1 ]]; then
  mlog "バックアップ: $BACKUP_DIR"
  [[ "$DRY_RUN" -eq 0 ]] && mkdir -p "$BACKUP_DIR" && cp -r "$CLAUDE_DIR" "$BACKUP_DIR/" || \
    mlog "[DRY-RUN] cp -r $CLAUDE_DIR $BACKUP_DIR/"
fi

# --- rsync ---
sync_dir() {
  local src="$1"
  local dest="$2"
  local label="$3"

  [[ ! -d "$src" ]] && return 0

  mlog "同期: $label ($src -> $dest)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    rsync -avzn --delete "$src/" "$dest/"
  else
    mkdir -p "$dest"
    rsync -avz --delete "$src/" "$dest/"
  fi
}

sync_dir "$KERNEL_RULES" "$CLAUDE_DIR/rules" "rules"
sync_dir "$KERNEL_HOOKS" "$CLAUDE_DIR/hooks" "hooks"

mlog "同期完了"
[[ "$DRY_RUN" -eq 1 ]] && mlog "(dry-runのため実際の変更はありません)"
