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

# oh-dispatch でIssueを処理
# バックグラウンド実行のためAnthropicAPI禁止（no-anthropic-api-background.md）
# OpenRouter → Groq のフォールバックチェーンで実行
OPENROUTER_KEY_FILE="${HOME}/.config/openrouter/moltbook-credentials.json"
GROQ_KEY_FILE="${HOME}/.config/groq/credentials.json"

if [[ -f "$OPENROUTER_KEY_FILE" ]]; then
  OR_KEY=$(jq -r '.api_key // empty' "$OPENROUTER_KEY_FILE" 2>/dev/null)
  BASE_URL_ARGS="--base-url https://openrouter.ai/api/v1 --api-key $OR_KEY"
elif [[ -f "$GROQ_KEY_FILE" ]]; then
  GROQ_KEY=$(jq -r '.api_key // empty' "$GROQ_KEY_FILE" 2>/dev/null)
  BASE_URL_ARGS="--base-url https://api.groq.com/openai/v1 --api-key $GROQ_KEY"
else
  echo "OpenRouter/Groq の認証情報が見つかりません。スキップします。" >&2
  exit 20
fi

oh-dispatch \
  --permission-mode full_auto \
  --max-turns "$MAX_TURNS" \
  $BASE_URL_ARGS \
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
