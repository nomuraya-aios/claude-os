#!/bin/bash
# meter/meter-parse-first-turn.sh
#
# 目的:
#   各セッションの「初回 cache_read > 0」エントリを抽出し、
#   新規セッション起動直後の実コスト（CLAUDE.md等の読み込み完了後）を計測する。
#
# 従来の meter-baseline-update.sh が「セッション全体の cache_read 合計」を
# 使っていたため、agent セッションや短いセッションが混入して過小評価していた。
# このスクリプトは「初回ターンで確定する固定コスト」のみを抽出する。
#
# 出力: JSON Lines（1行1セッション）
#   {"session_id": "...", "first_cr": N}
#
# 使用方法:
#   meter-parse-first-turn.sh               # 過去30日
#   meter-parse-first-turn.sh --all         # 全件（遅い）
#   meter-parse-first-turn.sh --stats       # 統計サマリのみ出力

set -euo pipefail

PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
SHOW_ALL=0
STATS_ONLY=0

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --all)   SHOW_ALL=1 ;;
    --stats) STATS_ONLY=1 ;;
  esac
  shift
done

# エージェントセッションを除外するフィルタ
is_agent_session() {
  local sid="$1"
  [[ "$sid" == agent-* ]] && return 0
  return 1
}

# 1セッションの「初回 cr > 0」を抽出
parse_first_cr() {
  local file="$1"
  local session
  session=$(basename "$file" .jsonl)

  # agent セッション除外
  is_agent_session "$session" && return 0

  # 初回の cache_read_input_tokens > 0 を取得
  local first_cr
  first_cr=$(jq -r '
    select(.type == "assistant")
    | .message.usage.cache_read_input_tokens // 0
    | select(. > 0)
  ' "$file" 2>/dev/null | head -1 || true)

  [[ -z "$first_cr" ]] && return 0

  echo "{\"session_id\": \"$session\", \"first_cr\": $first_cr}"
}

# ファイルリスト
if [[ "$SHOW_ALL" -eq 1 ]]; then
  FILE_LIST=$(find "$PROJECTS_DIR" -name "*.jsonl" | sort)
else
  FILE_LIST=$(find "$PROJECTS_DIR" -name "*.jsonl" -mtime -30 2>/dev/null | sort)
fi

if [[ "$STATS_ONLY" -eq 1 ]]; then
  # 統計サマリ出力
  echo "$FILE_LIST" | while read -r f; do
    [[ -z "$f" ]] && continue
    parse_first_cr "$f"
  done | jq -r '.first_cr' | sort -n | awk '
    BEGIN { n=0; sum=0 }
    { a[n++]=$1; sum+=$1 }
    END {
      if (n == 0) { print "{}"; exit }
      median = a[int(n/2)]
      p25    = a[int(n*0.25)]
      p75    = a[int(n*0.75)]
      printf "{\"median\": %d, \"p25\": %d, \"p75\": %d, \"mean\": %d, \"count\": %d}\n",
        median, p25, p75, int(sum/n), n
    }
  '
else
  echo "$FILE_LIST" | while read -r f; do
    [[ -z "$f" ]] && continue
    parse_first_cr "$f"
  done
fi
