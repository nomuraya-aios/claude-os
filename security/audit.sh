#!/bin/bash
# security/audit.sh
#
# 目的:
#   現環境のセキュリティ状態をチェックする。
#   banned-tools.yaml のパターンを .sh ファイルから検索し、
#   APIキーの平文記述・git-crypt 使用を検出して早期に警告する。
#   LLM不使用・bash + grep + awk のみ。
#
# 使用方法:
#   audit.sh [--dir <path>]
#   --dir: チェック対象ディレクトリ（デフォルト: ~/workspace-ai）
#
# exit code:
#   0  クリーン
#   1  WARNあり
#   2  ERRあり

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BANNED_YAML="$SCRIPT_DIR/banned-tools.yaml"
TARGET_DIR="$HOME/workspace-ai"

# 引数解析
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

warn_count=0
err_count=0

report_warn() {
  echo "[security] WARN: $1"
  warn_count=$((warn_count + 1))
}

report_err() {
  echo "[security] ERR : $1"
  err_count=$((err_count + 1))
}

report_ok() {
  echo "[security] OK  : $1"
}

# 1. banned-tools.yaml のパターンをシェルスクリプトから検索
if [[ -f "$BANNED_YAML" ]]; then
  # パターン行を抽出（YAML の pattern: "..." 形式から値を取得）
  while IFS= read -r line; do
    pattern=$(echo "$line" | sed 's/^[[:space:]]*pattern:[[:space:]]*//' | tr -d '"')
    [[ -z "$pattern" ]] && continue

    # シェルスクリプト(.sh)を検索
    while IFS= read -r -d '' file; do
      if grep -q "$pattern" "$file" 2>/dev/null; then
        report_warn "banned pattern '$pattern' in $file"
      fi
    done < <(find "$TARGET_DIR" -name "*.sh" -type f -print0 2>/dev/null)
  done < <(grep "pattern:" "$BANNED_YAML" 2>/dev/null)
else
  report_warn "banned-tools.yaml が見つからない（$BANNED_YAML）"
fi

# 2. APIキーパターン検索（.sh, .env, .yaml ファイル）
api_patterns=(
  'sk-[a-zA-Z0-9]{20,}'
  'ANTHROPIC_API_KEY='
  'ghp_[a-zA-Z0-9]+'
)

while IFS= read -r -d '' file; do
  for pat in "${api_patterns[@]}"; do
    if grep -qE "$pat" "$file" 2>/dev/null; then
      report_err "potential secret in $file"
      break  # 同一ファイルの重複報告を避ける
    fi
  done
done < <(find "$TARGET_DIR" \( -name "*.sh" -o -name "*.env" -o -name "*.yaml" \) -type f -print0 2>/dev/null)

# 3. git-crypt 使用確認
if git config --list 2>/dev/null | grep -qi "crypt"; then
  report_err "git-crypt detected"
else
  report_ok "git-crypt: 未使用"
fi

# 集計と終了
if [[ "$err_count" -gt 0 ]]; then
  echo "[security] 結果: WARN=${warn_count} / ERR=${err_count} → exit 2"
  exit 2
elif [[ "$warn_count" -gt 0 ]]; then
  echo "[security] 結果: WARN=${warn_count} / ERR=${err_count} → exit 1"
  exit 1
fi

echo "[security] 結果: クリーン"
exit 0
