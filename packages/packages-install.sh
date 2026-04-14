#!/bin/bash
# なぜ必要か:
# aios パッケージシステムのインストーラー。
# manifest.yaml に定義されたパッケージを source_dir から install_dest へコピーし、
# 依存コマンドの有無を検証する。これにより claude-os スキル・エージェント・モードを
# 宣言的に管理でき、手動コピーによるミスを防ぐ。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/manifest.yaml"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

log_info()  { echo "[packages] $*"; }
log_warn()  { echo "[packages] WARN: $*" >&2; }
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

# manifest.yaml をブロック単位で解析して指定パッケージの属性を取得する
# yq 不要 — grep/awk による行ベースパース
parse_package() {
  local name="$1"
  local attr="$2"
  # パッケージブロックは "- name: <name>" で始まり、次の "- name:" まで続く
  awk -v pkg="${name}" -v attr="${attr}" '
    /^  - name:/ {
      in_block = ($NF == pkg)
    }
    in_block && $0 ~ "^    " attr ":" {
      # キー: "value" から value を取り出す（クォート除去）
      val = $0
      sub(/^[^:]*: */, "", val)
      gsub(/^"|"$/, "", val)
      print val
      exit
    }
  ' "${MANIFEST}"
}

# deps リストを取得する（- item 形式の複数行）
parse_deps() {
  local name="$1"
  awk -v pkg="${name}" '
    /^  - name:/ {
      in_block = ($NF == pkg)
      in_deps  = 0
    }
    in_block && /^    deps:/ {
      in_deps = 1
      next
    }
    in_deps && /^      - / {
      val = $NF
      print val
    }
    in_deps && /^    [a-z]/ {
      in_deps = 0
    }
  ' "${MANIFEST}"
}

# パッケージが manifest に存在するか確認
VERSION="$(parse_package "${PKG_NAME}" "version")"
if [[ -z "${VERSION}" ]]; then
  log_error "パッケージが見つかりません: ${PKG_NAME}"
  exit 1
fi

SOURCE_DIR="$(parse_package "${PKG_NAME}" "source_dir")"
INSTALL_DEST="$(parse_package "${PKG_NAME}" "install_dest")"

# install_dest の ~ を展開
INSTALL_DEST="${INSTALL_DEST/#\~/$HOME}"

# source_dir の存在チェック
SOURCE_PATH="${REPO_ROOT}/${SOURCE_DIR}"
if [[ ! -d "${SOURCE_PATH}" ]]; then
  log_error "パッケージソースが見つかりません: ${SOURCE_PATH}"
  exit 1
fi

# deps チェック（不足していてもブロックしない — WARNのみ）
while IFS= read -r dep; do
  [[ -z "${dep}" ]] && continue
  if ! command -v "${dep}" &>/dev/null; then
    log_warn "依存コマンドが見つかりません: ${dep}"
  fi
done < <(parse_deps "${PKG_NAME}")

# インストール先の親ディレクトリを作成
mkdir -p "$(dirname "${INSTALL_DEST}")"

# コピー実行
cp -r "${SOURCE_PATH}" "${INSTALL_DEST}"

log_info "Installed: ${PKG_NAME} -> ${INSTALL_DEST}"
