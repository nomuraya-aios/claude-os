#!/bin/bash
# なぜ必要か:
# manifest.yaml に定義されたパッケージの一覧を表示する。
# --installed フラグを付けると install_dest が実際に存在するものだけを絞り込む。
# これにより「何が使えるか」と「何がインストール済みか」を素早く把握できる。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/manifest.yaml"

INSTALLED_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --installed) INSTALLED_ONLY=true ;;
    *) echo "使用方法: $(basename "$0") [--installed]" >&2; exit 1 ;;
  esac
done

# manifest.yaml から全パッケージの name/version/description/install_dest を抽出する
# yq 不要 — awk による行ベースパース
awk '
  /^  - name:/ {
    # 前のレコードを出力
    if (name != "") {
      print name "\t" version "\t" description "\t" install_dest
    }
    name = $NF; gsub(/^"|"$/, "", name)
    version = ""; description = ""; install_dest = ""
  }
  /^    version:/ {
    version = $NF; gsub(/^"|"$/, "", version)
  }
  /^    description:/ {
    # description はスペースを含む可能性があるため行全体から取得
    val = $0
    sub(/^[^:]*: */, "", val)
    gsub(/^"|"$/, "", val)
    description = val
  }
  /^    install_dest:/ {
    install_dest = $NF; gsub(/^"|"$/, "", install_dest)
  }
  END {
    if (name != "") {
      print name "\t" version "\t" description "\t" install_dest
    }
  }
' "${MANIFEST}" | while IFS=$'\t' read -r name version description install_dest; do
  if [[ "${INSTALLED_ONLY}" == true ]]; then
    # install_dest の ~ を展開して存在確認
    dest="${install_dest/#\~/$HOME}"
    if [[ ! -d "${dest}" ]]; then
      continue
    fi
  fi
  printf "%s\t%s\t%s\n" "${name}" "${version}" "${description}"
done
