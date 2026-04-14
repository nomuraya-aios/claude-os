#!/bin/bash
# meter/meter-parse-session.sh
#
# 目的:
#   ~/.claude/projects/**/*.jsonl からセッションのトークン消費を集計する。
#   LLM不使用・grep+jq+awkのみ。1ファイル1回のjq呼び出しで高速化。
#
# 使用方法:
#   meter-parse-session.sh                    # 今日分
#   meter-parse-session.sh --date 2026-04-14  # 指定日
#   meter-parse-session.sh --session <id>     # セッション単位
#   meter-parse-session.sh --all              # 全件（遅い）
#
# 出力: JSON Lines
#   {"session_id": "...", "date": "...", "input": N, "cache_read": N, "output": N, "total": N}

set -euo pipefail

PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
TARGET_DATE=""
SESSION_ID=""
SHOW_ALL=0

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --date)    shift; TARGET_DATE="${1:-}" ;;
    --session) shift; SESSION_ID="${1:-}" ;;
    --all)     SHOW_ALL=1 ;;
  esac
  shift
done

# デフォルトは今日
if [[ -z "$TARGET_DATE" && -z "$SESSION_ID" && "$SHOW_ALL" -eq 0 ]]; then
  TARGET_DATE=$(TZ=Asia/Tokyo date '+%Y-%m-%d')
fi

# jsonlファイルをスキャンしてusageフィールドを集計
scan_jsonl() {
  local file="$1"
  local session
  session=$(basename "$file" .jsonl)

  # セッション指定フィルタ
  if [[ -n "$SESSION_ID" && "$session" != "$SESSION_ID" ]]; then
    return 0
  fi

  # ファイル日付を先に取得してフィルタ（無駄なgrep/jqを防ぐ）
  local file_date
  file_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$file" 2>/dev/null \
    || stat -c "%y" "$file" 2>/dev/null | cut -c1-10)

  if [[ -n "$TARGET_DATE" && "$file_date" != "$TARGET_DATE" ]]; then
    return 0
  fi

  # usageをjqで一括集計（message.usageフィールドを直接抽出）
  local result
  result=$(jq -sc '
      [.[] | .message.usage // empty | select(.input_tokens != null)] |
      if length == 0 then empty
      else {
        input:      ([.[].input_tokens // 0] | add),
        cache_read: ([.[].cache_read_input_tokens // 0] | add),
        output:     ([.[].output_tokens // 0] | add)
      } end
    ' "$file" 2>/dev/null) || return 0

  [[ -z "$result" ]] && return 0

  local total
  total=$(echo "$result" | jq -r '(.input + .cache_read + .output)')
  [[ "$total" -le 0 ]] && return 0

  echo "$result" | jq -c \
    --arg sid "$session" \
    --arg date "$file_date" \
    --argjson total "$total" \
    '. + {session_id: $sid, date: $date, total: $total}'
}

# ファイルリスト作成
# --all以外は直近30日に限定（3000+ファイルの全スキャン防止）
if [[ "$SHOW_ALL" -eq 1 ]]; then
  FILE_LIST=$(find "$PROJECTS_DIR" -name "*.jsonl" | sort)
elif [[ -n "$SESSION_ID" ]]; then
  FILE_LIST=$(find "$PROJECTS_DIR" -name "${SESSION_ID}.jsonl" 2>/dev/null)
else
  FILE_LIST=$(find "$PROJECTS_DIR" -name "*.jsonl" -mtime -30 2>/dev/null)
fi

echo "$FILE_LIST" | while read -r f; do
  [[ -z "$f" ]] && continue
  scan_jsonl "$f"
done
