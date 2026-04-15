#!/bin/bash
# Stop hook: memory の feedback ファイルから feedback.jsonl へ自動同期
#
# なぜ必要か:
#   AIがセッション中にユーザーの訂正を memory/feedback_*.md に記録するが、
#   これが engineering-feedback/feedback.jsonl に自動反映されていなかった。
#   2つのフィードバック経路を統合し、改善ループの入口を自動化する。
#
# 動作:
#   1. memory/ 配下の feedback_*.md を走査
#   2. feedback.jsonl に未記録のものを追加
#   3. 非同期実行（Stop hook をブロックしない）

cat > /dev/null  # stdin消費

FEEDBACK_FILE="$HOME/.claude/engineering-feedback/feedback.jsonl"
SYNC_MARKER="$HOME/.claude/state/feedback-sync-marker"

mkdir -p "$(dirname "$FEEDBACK_FILE")" "$(dirname "$SYNC_MARKER")"

# 最終同期時刻（なければ epoch）
LAST_SYNC=0
if [[ -f "$SYNC_MARKER" ]]; then
    LAST_SYNC=$(cat "$SYNC_MARKER")
fi

SYNCED=0

# 全プロジェクト memory の feedback_*.md を走査
find "$HOME/.claude/projects" -name "feedback_*.md" -newer "$SYNC_MARKER" 2>/dev/null | while read -r file; do
    # frontmatter から type: feedback を確認
    if ! head -10 "$file" | grep -q "type: feedback"; then
        continue
    fi

    # ファイル名をIDに使う
    FILE_ID=$(basename "$file" .md)

    # 既にfeedback.jsonlに記録済みか確認
    if [[ -f "$FEEDBACK_FILE" ]] && grep -q "\"memory_id\":\"$FILE_ID\"" "$FEEDBACK_FILE" 2>/dev/null; then
        continue
    fi

    # frontmatter の description を抽出
    DESCRIPTION=$(sed -n '/^description:/s/description: *//p' "$file" | head -1)
    if [[ -z "$DESCRIPTION" ]]; then
        DESCRIPTION=$(head -1 "$file" | sed 's/^# *//')
    fi

    # body（frontmatter以降）を抽出
    BODY=$(awk '/^---$/{c++; next} c>=2' "$file" | head -5 | tr '\n' ' ')

    # feedback.jsonl に追記
    if command -v jq >/dev/null 2>&1; then
        jq -n -c \
            --arg id "$(uuidgen 2>/dev/null || echo "mem-$(date +%s)")" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --arg feedback "$DESCRIPTION $BODY" \
            --arg category "process" \
            --arg scope "claude_code" \
            --arg memory_id "$FILE_ID" \
            '{id: $id, ts: $ts, session_id: "auto-sync", feedback: $feedback,
              category: $category, scope: $scope, memory_id: $memory_id,
              affected_components: [], processed: false}' \
            >> "$FEEDBACK_FILE"
        SYNCED=$((SYNCED + 1))
    fi
done

# 同期マーカー更新
date +%s > "$SYNC_MARKER"

# ログ（ブロックしない）
if [[ "$SYNCED" -gt 0 ]]; then
    echo "[feedback-sync] ${SYNCED}件のmemory feedbackをfeedback.jsonlに同期" \
        >> "$HOME/.claude/state/feedback-sync.log"
fi

exit 0
