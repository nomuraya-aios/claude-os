#!/bin/bash
# deploy/sync.sh
#
# 目的:
#   kernel/ のルール・hookを ~/.claude/ にマージ（追加）する。
#   --delete は使わず、既存の設定を壊さずに claude-os の設定を追加する。
#   他ユーザーが自分の設定に上書きされるリスクを排除するため、
#   追加専用（ファイルが既に存在する場合はスキップ or --force で上書き）。
#
# 使用方法:
#   sync.sh [--dry-run] [--backup] [--force]
#   --dry-run : 変更せず差分を表示
#   --backup  : 同期前に ~/.claude/ をバックアップ
#   --force   : 既存ファイルを上書き（デフォルトはスキップ）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AIOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL_DIR="$AIOS_ROOT/kernel"
CLAUDE_DIR="${HOME}/.claude"
BACKUP_DIR="${HOME}/.local/share/claude-os/backups/$(TZ=UTC date '+%Y%m%dT%H%M%SZ')"

DRY_RUN=0
DO_BACKUP=0
FORCE=0
ADDED=0
SKIPPED=0

mlog()  { echo "[sync] $*"; }
mwarn() { echo "[sync] WARN: $*" >&2; }
merr()  { echo "[sync] ERR: $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --dry-run) DRY_RUN=1 ;;
    --backup)  DO_BACKUP=1 ;;
    --force)   FORCE=1 ;;
  esac
  shift
done

KERNEL_RULES="$KERNEL_DIR/rules"
KERNEL_HOOKS="$KERNEL_DIR/hooks"

# --- kernel が実質空（.gitkeep のみ）なら安全ブロック ---
check_kernel_not_empty() {
  local dir="$1"
  [[ ! -d "$dir" ]] && return 0
  local count
  count=$(find "$dir" -type f ! -name ".gitkeep" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$count" -eq 0 ]]; then
    merr "$dir が空です（.gitkeepのみ）。配布可能なルール・hookがありません。"
    exit 1
  fi
}

check_kernel_not_empty "$KERNEL_RULES"
check_kernel_not_empty "$KERNEL_HOOKS"

# --- バックアップ ---
if [[ "$DO_BACKUP" -eq 1 && "$DRY_RUN" -eq 0 ]]; then
  mlog "バックアップ: $BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"
  cp -r "$CLAUDE_DIR" "$BACKUP_DIR/"
fi

# --- 追加マージ（--delete なし）---
# 既存ファイルはスキップ（--force で上書き可）
merge_dir() {
  local src="$1"
  local dest="$2"
  local label="$3"

  [[ ! -d "$src" ]] && return 0

  mlog "マージ: $label"
  mkdir -p "$dest"

  while IFS= read -r -d '' src_file; do
    local rel_path="${src_file#$src/}"
    local dest_file="$dest/$rel_path"
    local dest_parent
    dest_parent="$(dirname "$dest_file")"

    # .gitkeep はスキップ
    [[ "$(basename "$src_file")" == ".gitkeep" ]] && continue

    if [[ -f "$dest_file" && "$FORCE" -eq 0 ]]; then
      mlog "  SKIP (既存): $rel_path"
      SKIPPED=$((SKIPPED + 1))
    else
      if [[ "$DRY_RUN" -eq 1 ]]; then
        mlog "  ADD (dry-run): $rel_path"
      else
        mkdir -p "$dest_parent"
        cp "$src_file" "$dest_file"
        mlog "  ADD: $rel_path"
      fi
      ADDED=$((ADDED + 1))
    fi
  done < <(find "$src" -type f -print0)
}

merge_dir "$KERNEL_RULES" "$CLAUDE_DIR/rules" "rules"
merge_dir "$KERNEL_HOOKS" "$CLAUDE_DIR/hooks" "hooks"

mlog ""
mlog "同期完了: 追加=${ADDED} / スキップ=${SKIPPED}"
[[ "$DRY_RUN" -eq 1 ]] && mlog "(dry-runのため実際の変更はありません)"
[[ "$SKIPPED" -gt 0 && "$FORCE" -eq 0 ]] && mlog "※ 上書きするには --force を使ってください"
