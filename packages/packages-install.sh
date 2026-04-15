#!/bin/bash
# なぜ必要か:
# aios パッケージシステムのインストーラー。
# manifest.yaml に定義されたパッケージを source_dir から install_dest へコピーし、
# 依存コマンドの有無を検証する。これにより claude-os スキル・エージェント・モードを
# 宣言的に管理でき、手動コピーによるミスを防ぐ。
#
# 設計原則: ユーザーの既存環境を壊さない
#   - install_dest が既に存在する場合はスキップ（--force で上書き可）
#   - CLAUDE.md のトリガー注入も既存エントリがあればスキップ（冪等）
#   - claude-os がウイルス的な振る舞いをしないための最重要ルール

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/manifest.yaml"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

log_info()  { echo "[packages] $*"; }
log_warn()  { echo "[packages] WARN: $*" >&2; }
log_error() { echo "[packages] ERROR: $*" >&2; }

FORCE=0

usage() {
  echo "使用方法: $(basename "$0") <name> [--force]"
  echo "  name:    manifest.yaml に定義されたパッケージ名"
  echo "  --force: 既存スキルを上書き（デフォルトはスキップ）"
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

PKG_NAME="${1:-}"
shift
while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --force) FORCE=1 ;;
    *) log_error "不明なオプション: ${1:-}"; usage ;;
  esac
  shift
done

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

# manifest.yaml から trigger フィールドを取得する
get_trigger() {
  local name="$1"
  awk "
    /^  - name: ${name}\$/ { found=1 }
    found && /^    trigger:/ { gsub(/^    trigger: */, \"\"); gsub(/^\"/,\"\"); gsub(/\"\$/,\"\"); print; exit }
    found && /^  - name:/ && !/^  - name: ${name}/ { exit }
  " "${MANIFEST}"
}

# CLAUDE.md へトリガー行を注入する
# 既に同名スキルのエントリがあればスキップ（冪等）
inject_trigger() {
  local name="$1"
  local trigger="$2"
  local claude_md="${HOME}/.claude/CLAUDE.md"

  # CLAUDE.md が存在しない場合はスキップ
  if [[ ! -f "$claude_md" ]]; then
    log_warn "CLAUDE.md が見つかりません。トリガー注入をスキップ: ${claude_md}"
    return 0
  fi

  # 既に同じ name のトリガーが入っていればスキップ
  if grep -q "claude-os-skill:${name}" "$claude_md" 2>/dev/null; then
    log_info "trigger 既存スキップ: $name"
    return 0
  fi

  # マーカーセクションが存在しなければ末尾に追加
  local marker="<!-- claude-os skills -->"
  if ! grep -q "${marker}" "$claude_md"; then
    printf "\n%s\n" "${marker}" >> "$claude_md"
  fi

  # マーカーの後にトリガー行を追記
  # 形式: <!-- claude-os-skill:name --> trigger_text
  local inject_line="<!-- claude-os-skill:${name} --> ${trigger}"
  # macOS sed で marker の後に行を挿入
  sed -i '' "/${marker}/a\\
${inject_line}" "$claude_md"

  log_info "trigger 注入: $name -> $claude_md"
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

# 既存チェック — ユーザーの環境を壊さないための最重要ガード
if [[ -d "${INSTALL_DEST}" ]]; then
  if [[ "$FORCE" -eq 0 ]]; then
    log_info "スキップ（既存）: ${PKG_NAME} -- 上書きするには --force を使用"
    exit 0
  else
    log_warn "上書き: ${PKG_NAME} (--force 指定)"
  fi
fi

# インストール先の親ディレクトリを作成
mkdir -p "$(dirname "${INSTALL_DEST}")"

# コピー実行
cp -r "${SOURCE_PATH}" "${INSTALL_DEST}"

log_info "Installed: ${PKG_NAME} -> ${INSTALL_DEST}"

# CLAUDE.md へのトリガー注入
TRIGGER="$(get_trigger "${PKG_NAME}")"
[[ -n "${TRIGGER}" ]] && inject_trigger "${PKG_NAME}" "${TRIGGER}"
