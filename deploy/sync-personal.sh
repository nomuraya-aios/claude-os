#!/bin/bash
# deploy/sync-personal.sh
#
# 目的:
#   personal リポジトリ（~/.claude を管理する git repo）の変更を
#   ~/.claude/ に追加マージする。
#   claude-os の kernel とは別レイヤーとして管理することで、
#   OS共通設定（kernel）とユーザー固有設定（personal）を独立して更新できる。
#
# 使用方法:
#   sync-personal.sh [--dry-run] [--config <path>]
#   --dry-run: 変更せず差分を表示
#   --config:  aios.config.yaml のパス（デフォルト: $AIOS_ROOT/config/aios.config.yaml）
#
# exit codes: 0=成功/スキップ / 1=エラー

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AIOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CLAUDE_DIR="${HOME}/.claude"
BACKUP_DIR="${HOME}/.local/share/claude-os/backups/personal-$(TZ=UTC date '+%Y%m%dT%H%M%SZ')"

DRY_RUN=0
CONFIG_PATH="$AIOS_ROOT/config/aios.config.yaml"
ADDED=0
SKIPPED=0

mlog()  { echo "[sync-personal] $*"; }
mwarn() { echo "[sync-personal] WARN: $*" >&2; }
merr()  { echo "[sync-personal] ERR: $*" >&2; }

# --- 引数パース ---
while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --dry-run)
      DRY_RUN=1
      ;;
    --config)
      shift
      CONFIG_PATH="${1:-}"
      ;;
    *)
      merr "不明なオプション: ${1:-}"
      exit 1
      ;;
  esac
  shift
done

# --- config 読み込み（grep/awk のみ、yq/python 不可）---
if [[ ! -f "$CONFIG_PATH" ]]; then
  mwarn "config が見つかりません: $CONFIG_PATH — personal 機能をスキップ"
  exit 0
fi

# personal_repo の値を抽出
# "key: value  # comment" 形式に対応: コメント(#以降)を除去してから値を取得
PERSONAL_REPO="$(grep -E '^personal_repo:' "$CONFIG_PATH" \
  | sed 's/#.*//' \
  | awk -F': ' '{print $2}' \
  | tr -d ' "'"'" \
  | head -1)"

if [[ -z "$PERSONAL_REPO" ]]; then
  mwarn "personal_repo が未設定です — personal 機能をスキップ"
  exit 0
fi

# enabled フラグを確認（personal_deploy ブロック内 enabled: の値）
# awk で personal_deploy: セクション開始後の最初の enabled: 行を取得
ENABLED="$(awk '
  BEGIN { in_block=0 }
  /^personal_deploy:/ { in_block=1; next }
  in_block && /^[[:space:]]+enabled:/ { gsub(/.*enabled:[[:space:]]*/, ""); gsub(/#.*/, ""); gsub(/[[:space:]]/, ""); print; exit }
  in_block && /^[^ ]/ { exit }
' "$CONFIG_PATH")"

if [[ "$ENABLED" != "true" ]]; then
  mwarn "personal_deploy.enabled が false — personal 機能をスキップ"
  exit 0
fi

# backup フラグを確認
BACKUP_FLAG="$(awk '
  BEGIN { in_block=0 }
  /^personal_deploy:/ { in_block=1; next }
  in_block && /^[[:space:]]+backup:/ { gsub(/.*backup:[[:space:]]*/, ""); gsub(/#.*/, ""); gsub(/[[:space:]]/, ""); print; exit }
  in_block && /^[^ ]/ { exit }
' "$CONFIG_PATH")"

# ~ を $HOME に展開
PERSONAL_REPO="${PERSONAL_REPO/#\~/$HOME}"

# --- バリデーション ---
if [[ ! -d "$PERSONAL_REPO" ]]; then
  merr "personal_repo のパスが存在しません: $PERSONAL_REPO"
  exit 1
fi

if [[ ! -d "$PERSONAL_REPO/.git" ]]; then
  merr "personal_repo が git リポジトリではありません: $PERSONAL_REPO"
  exit 1
fi

mlog "personal_repo: $PERSONAL_REPO"

# --- git pull --ff-only で最新化 ---
if [[ "$DRY_RUN" -eq 0 ]]; then
  mlog "git pull --ff-only..."
  git -C "$PERSONAL_REPO" pull --ff-only || {
    mwarn "git pull に失敗しました（コンフリクトの可能性）。手動で解決してください。"
    exit 1
  }
else
  mlog "(dry-run) git pull はスキップ"
fi

# --- バックアップ ---
if [[ "$BACKUP_FLAG" == "true" && "$DRY_RUN" -eq 0 ]]; then
  mlog "バックアップ: $BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"
  cp -r "$CLAUDE_DIR" "$BACKUP_DIR/"
fi

# --- 追加マージ（--delete なし、.git/.gitignore 除外）---
merge_personal() {
  local src="$1"
  local dest="$2"

  mkdir -p "$dest"

  while IFS= read -r -d '' src_file; do
    local rel_path="${src_file#$src/}"

    # .git/ を除外
    [[ "$rel_path" == .git* ]] && continue
    # .gitignore を除外
    [[ "$(basename "$src_file")" == ".gitignore" ]] && continue
    # .gitkeep はスキップ
    [[ "$(basename "$src_file")" == ".gitkeep" ]] && continue

    local dest_file="$dest/$rel_path"
    local dest_parent
    dest_parent="$(dirname "$dest_file")"

    if [[ -f "$dest_file" ]]; then
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

mlog "マージ: personal_repo → $CLAUDE_DIR"
merge_personal "$PERSONAL_REPO" "$CLAUDE_DIR"

mlog ""
mlog "同期完了: 追加=${ADDED} / スキップ=${SKIPPED}"
[[ "$DRY_RUN" -eq 1 ]] && mlog "(dry-runのため実際の変更はありません)"
