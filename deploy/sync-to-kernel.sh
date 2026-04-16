#!/bin/bash
# deploy/sync-to-kernel.sh
#
# 目的:
#   ~/.claude/rules/ と hooks/ の実運用状態を kernel/ に反映する。
#   正本は ~/.claude（実運用で改善される）。kernel は配布元。
#
# 使用方法:
#   sync-to-kernel.sh [--dry-run]
#
# 同期対象:
#   kernel/rules/ の既存ファイルのみ更新（新規追加はしない）
#   kernel/hooks/ の既存ファイルのみ更新（新規追加はしない）
#   → ローカル固有ファイル（user-behavior-style.md 等）は kernel に入らない
#
# 運用:
#   aios sync-to-kernel --dry-run で差分確認 → 問題なければ実行 → commit & push

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AIOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL_DIR="$AIOS_ROOT/kernel"
CLAUDE_DIR="${HOME}/.claude"

DRY_RUN=0
UPDATED=0
UNCHANGED=0

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# kernel の既存ファイルのみ更新（新規追加はしない）
sync_dir() {
  local kernel_sub="$1"
  local claude_sub="$2"
  local label="$3"

  [ ! -d "$kernel_sub" ] && return 0

  for kf in "$kernel_sub"/*; do
    [ ! -f "$kf" ] && continue
    name=$(basename "$kf")
    [ "$name" = ".gitkeep" ] && continue

    cf="$claude_sub/$name"
    if [ ! -f "$cf" ]; then
      echo "  SKIP (実運用に存在しない): $label/$name"
      continue
    fi

    if diff -q "$kf" "$cf" >/dev/null 2>&1; then
      UNCHANGED=$((UNCHANGED + 1))
    else
      if [ "$DRY_RUN" -eq 1 ]; then
        echo "  UPDATE (dry-run): $label/$name"
        diff --unified=3 "$kf" "$cf" | head -20
      else
        cp "$cf" "$kf"
        echo "  UPDATE: $label/$name"
      fi
      UPDATED=$((UPDATED + 1))
    fi
  done
}

echo "=== sync-to-kernel: ~/.claude → kernel ==="
sync_dir "$KERNEL_DIR/rules" "$CLAUDE_DIR/rules" "rules"
sync_dir "$KERNEL_DIR/hooks" "$CLAUDE_DIR/hooks" "hooks"

echo ""
echo "結果: 更新=${UPDATED} / 変更なし=${UNCHANGED}"
[ "$DRY_RUN" -eq 1 ] && echo "(dry-run: 実際の変更はありません)"

if [ "$UPDATED" -gt 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  echo ""
  echo "次のステップ:"
  echo "  cd $AIOS_ROOT && git add kernel/ && git commit -m 'sync: kernel を実運用に同期' && git push"
fi
