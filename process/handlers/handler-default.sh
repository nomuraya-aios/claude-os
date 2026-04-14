#!/bin/bash
# process/handlers/handler-default.sh
#
# 目的:
#   ラベル固有ハンドラが存在しない場合のデフォルト処理。
#   IssueタイトルとボディをAIに渡してoh-dispatchで実行する。
#
# 安全制約:
#   --max-turns は呼び出し元(process-runner.sh)から受け取る（上書き禁止）

set -euo pipefail

REPO=""
ISSUE_NUMBER=""
MAX_TURNS=20

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --repo)       shift; REPO="${1:-}" ;;
    --issue)      shift; ISSUE_NUMBER="${1:-}" ;;
    --max-turns)  shift; MAX_TURNS="${1:-20}" ;;
  esac
  shift
done

if [[ -z "$REPO" || -z "$ISSUE_NUMBER" ]]; then
  echo "REPO と ISSUE_NUMBER が必要です" >&2
  exit 1
fi

# Issue内容取得
ISSUE_JSON=$(gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json title,body,labels)
TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
BODY=$(echo "$ISSUE_JSON" | jq -r '.body // ""')
LABELS=$(echo "$ISSUE_JSON" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')

# oh-dispatch が使えるか確認
if ! command -v oh-dispatch &>/dev/null; then
  echo "oh-dispatch が見つかりません。スキップします。" >&2
  exit 20
fi

# oh-dispatch でIssueを処理（max-turns上限必須）
oh-dispatch \
  --permission-mode full_auto \
  --max-turns "$MAX_TURNS" \
  -p "$(cat <<EOF
以下のGitHub Issueを処理してください。

リポジトリ: $REPO
Issue #$ISSUE_NUMBER: $TITLE
ラベル: $LABELS

本文:
$BODY

処理が完了したら、実施内容を簡潔にまとめて出力してください。
EOF
)"

exit 0
