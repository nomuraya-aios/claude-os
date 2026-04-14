#!/bin/bash
# security/pre-commit-check.sh
#
# 目的:
#   git pre-commit フックとして使用し、コミット前にsecrets（APIキー等）の
#   平文混入を検出してコミットをブロックする。
#   誤ってAPIキーをリポジトリに含めるヒューマンエラーを防ぐ。
#   LLM不使用・bash + grep のみ。
#
# 使用方法:
#   .git/hooks/pre-commit として配置するか symlink を張る
#   直接実行: pre-commit-check.sh
#
# exit code:
#   0  クリーン（コミット許可）
#   1  シークレット検出（コミットブロック）

set -euo pipefail

# ステージ済みファイルを取得
staged_files=$(git diff --cached --name-only 2>/dev/null || true)

if [[ -z "$staged_files" ]]; then
  exit 0
fi

found=0

# チェックするAPIキーパターン
api_patterns=(
  'sk-[a-zA-Z0-9]{20,}'
  'ANTHROPIC_API_KEY\s*='
  'ghp_[a-zA-Z0-9]+'
)

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  [[ ! -f "$file" ]] && continue  # 削除済みファイルはスキップ

  for pat in "${api_patterns[@]}"; do
    if git diff --cached -- "$file" | grep -qE "^\+.*${pat}" 2>/dev/null; then
      echo "[pre-commit] BLOCK: secret detected in $file"
      found=1
      break
    fi
  done
done <<< "$staged_files"

if [[ "$found" -eq 1 ]]; then
  echo "[pre-commit] コミットをブロックしました。シークレットを削除してから再度コミットしてください。"
  exit 1
fi

exit 0
