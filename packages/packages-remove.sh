#!/bin/bash
# なぜ必要か:
# manifest.yaml に定義されたパッケージの install_dest を削除する。
# rm -rf は絶対禁止のため trash コマンドを使う。
# これにより誤削除時もゴミ箱から復元できる安全な削除を実現する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/manifest.yaml"

log_info()  { echo "[packages] $*"; }
log_error() { echo "[packages] ERROR: $*" >&2; }

usage() {
  echo "使用方法: $(basename "$0") <name>"
  echo "  name: manifest.yaml に定義されたパッケージ名"
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
fi

PKG_NAME="$1"

# trash コマンドの存在確認
if ! command -v trash &>/dev/null; then
  log_error "trash コマンドが見つかりません。brew install trash でインストールしてください。"
  exit 1
fi

# manifest.yaml から install_dest を取得する
parse_package() {
  local name="$1"
  local attr="$2"
  awk -v pkg="${name}" -v attr="${attr}" '
    /^  - name:/ {
      in_block = ($NF == pkg)
    }
    in_block && $0 ~ "^    " attr ":" {
      val = $0
      sub(/^[^:]*: */, "", val)
      gsub(/^"|"$/, "", val)
      print val
      exit
    }
  ' "${MANIFEST}"
}

# パッケージが manifest に存在するか確認
VERSION="$(parse_package "${PKG_NAME}" "version")"
if [[ -z "${VERSION}" ]]; then
  log_error "パッケージが見つかりません: ${PKG_NAME}"
  exit 1
fi

INSTALL_DEST="$(parse_package "${PKG_NAME}" "install_dest")"
# install_dest の ~ を展開
INSTALL_DEST="${INSTALL_DEST/#\~/$HOME}"

if [[ ! -d "${INSTALL_DEST}" ]]; then
  log_info "Not installed: ${PKG_NAME}"
  exit 0
fi

trash "${INSTALL_DEST}"
log_info "Removed: ${PKG_NAME} (${INSTALL_DEST})"
