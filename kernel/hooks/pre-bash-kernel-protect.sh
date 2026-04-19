#!/usr/bin/env bash
# kernel/hooks/pre-bash-kernel-protect.sh
#
# kernel/配下への変更操作をブロックする。
# AIが意図せずkernelを変更することを防ぐ。
#
# ブロック対象:
#   - kernel/配下のファイルを引数に取るWrite/Edit操作
#   - kernel/配下を対象にしたrm/mv/cp
#
# 通過条件:
#   - ユーザーが明示的に「kernel編集モード」と指示した場合
#     → 環境変数 KERNEL_EDIT_AUTHORIZED=1 をセットして実行

set -euo pipefail

COMMAND="${1:-}"
KERNEL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# kernel編集が明示的に承認されている場合はスルー
if [[ "${KERNEL_EDIT_AUTHORIZED:-0}" == "1" ]]; then
  exit 0
fi

# コマンド内にkernelパスが含まれているか検査
if echo "$COMMAND" | grep -qF "$KERNEL_DIR"; then
  # 読み取り操作（cat/ls/grep/head/tail）は許可
  if echo "$COMMAND" | grep -qE "^(cat|ls|grep|head|tail|find|echo)\s"; then
    exit 0
  fi

  echo "" >&2
  echo "❌ [kernel-protect] kernel/への変更操作はブロックされました" >&2
  echo "" >&2
  echo "   対象: $KERNEL_DIR" >&2
  echo "   kernel/はユーザー（shimajima-eiji）のみが変更できます。" >&2
  echo "" >&2
  echo "   変更が必要な場合は、ユーザーが明示的に指示してください。" >&2
  echo "   （AIはkernel/の変更・削除・移動を提案してはなりません）" >&2
  echo "" >&2
  exit 1
fi

exit 0
