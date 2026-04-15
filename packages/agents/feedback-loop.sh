#!/bin/bash
# feedback-loop.sh — フィードバック自己改善ループの統合エントリポイント
#
# なぜ必要か:
#   フィードバック収集(engineering-feedback) と改善実行(agent-system-improver.sh) が
#   分離しており手動でしか接続されていなかった。このスクリプトは両者を統合し、
#   「収集 → 改善 → 検証 → 学習」の自動ループを回す。
#
# 設計原則（anti-rally-engineering に基づく）:
#   - 修復スクリプトを増やさない。壊れない仕組みを作る
#   - フォールバックは最大2段
#   - oh-dispatch は1実行1回（ループ呼び出し禁止）
#
# 使用方法:
#   bash feedback-loop.sh collect   — 未処理フィードバックの集計・分類
#   bash feedback-loop.sh improve   — 改善PR生成（oh-dispatch 1回）
#   bash feedback-loop.sh status    — 改善ループの状態確認
#   bash feedback-loop.sh report    — 週次改善レポート

set -euo pipefail

FEEDBACK_FILE="$HOME/.claude/engineering-feedback/feedback.jsonl"
IMPROVEMENT_AGENT="$HOME/workspace-ai/nomuraya-agent-openclaw/moltbook/scripts/agent-system-improver.sh"
AIOS_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$AIOS_DIR/logging"

mkdir -p "$LOG_DIR" "$(dirname "$FEEDBACK_FILE")"

log() { echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%dT%H:%M:%S')] [feedback-loop] $*"; }

# --- collect: 未処理フィードバックの集計 ---
cmd_collect() {
    if [[ ! -f "$FEEDBACK_FILE" ]]; then
        log "feedback.jsonl が存在しません"
        exit 0
    fi

    local total unprocessed
    total=$(wc -l < "$FEEDBACK_FILE" | tr -d ' ')
    unprocessed=$(jq -r 'select(.processed == false or .processed == null) | .id' "$FEEDBACK_FILE" 2>/dev/null | wc -l | tr -d ' ')

    log "合計: ${total}件, 未処理: ${unprocessed}件"

    if [[ "$unprocessed" -eq 0 ]]; then
        log "未処理フィードバックなし"
        exit 0
    fi

    # カテゴリ別集計
    log "カテゴリ別:"
    jq -r 'select(.processed == false or .processed == null) | .category // "unknown"' "$FEEDBACK_FILE" 2>/dev/null \
        | sort | uniq -c | sort -rn | while read -r count cat; do
        log "  ${cat}: ${count}件"
    done

    # 最新5件のフィードバックを表示
    log "最新の未処理フィードバック:"
    jq -r 'select(.processed == false or .processed == null) | "  [\(.ts // "?")] \(.category // "?"): \(.feedback // "?" | .[0:100])"' "$FEEDBACK_FILE" 2>/dev/null \
        | tail -5
}

# --- improve: 改善PR生成 ---
cmd_improve() {
    cmd_collect

    if [[ ! -f "$IMPROVEMENT_AGENT" ]]; then
        log "ERROR: agent-system-improver.sh が見つかりません: $IMPROVEMENT_AGENT"
        exit 1
    fi

    if ! command -v oh-dispatch &>/dev/null; then
        log "SKIP: oh-dispatch が未インストール"
        exit 0
    fi

    log "改善エージェントを実行..."
    bash "$IMPROVEMENT_AGENT" "$@"
}

# --- status: 改善ループの状態確認 ---
cmd_status() {
    echo "=== nomuraya-aios feedback loop status ==="
    echo ""

    # フィードバック状況
    if [[ -f "$FEEDBACK_FILE" ]]; then
        local total unprocessed
        total=$(wc -l < "$FEEDBACK_FILE" | tr -d ' ')
        unprocessed=$(jq -r 'select(.processed == false or .processed == null) | .id' "$FEEDBACK_FILE" 2>/dev/null | wc -l | tr -d ' ')
        echo "📝 フィードバック: ${total}件 (未処理: ${unprocessed}件)"
    else
        echo "📝 フィードバック: なし"
    fi

    # hook状態
    echo ""
    echo "🔗 Hook:"
    for hook in post-edit-shell-quality-gate.sh; do
        if [[ -x "$HOME/.claude/hooks/$hook" ]]; then
            echo "  ✅ $hook"
        else
            echo "  ❌ $hook (未設置)"
        fi
    done

    # 改善エージェント状態
    echo ""
    echo "🤖 改善エージェント:"
    if [[ -f "$IMPROVEMENT_AGENT" ]]; then
        echo "  ✅ agent-system-improver.sh"
    else
        echo "  ❌ agent-system-improver.sh (未設置)"
    fi

    if command -v oh-dispatch &>/dev/null; then
        echo "  ✅ oh-dispatch $(oh-dispatch --version 2>/dev/null | head -1 || echo '(version unknown)')"
    else
        echo "  ❌ oh-dispatch (未インストール)"
    fi

    # ルール状態
    echo ""
    echo "📋 ルール:"
    for rule in anti-rally-engineering.md no-llm-autonomous-loop.md no-anthropic-api-background.md; do
        if [[ -f "$HOME/.claude/rules/$rule" ]]; then
            echo "  ✅ $rule"
        else
            echo "  ❌ $rule"
        fi
    done

    # セッション統計（直近7日）
    echo ""
    echo "📊 直近7日のセッション分類:"
    if [[ -d "$HOME/ai-tasklogs/sessions" ]]; then
        local fix_count total_count
        fix_count=$(find "$HOME/ai-tasklogs/sessions" -name "*.md" -newer /tmp/aios-7days-marker -type f 2>/dev/null \
            | xargs grep -l "repair\|fix\|hotfix\|recover\|broken" 2>/dev/null | wc -l | tr -d ' ')
        total_count=$(find "$HOME/ai-tasklogs/sessions" -name "*.md" -newer /tmp/aios-7days-marker -type f 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$total_count" -gt 0 ]]; then
            local ratio=$((fix_count * 100 / total_count))
            echo "  修正系: ${fix_count}/${total_count} (${ratio}%)"
            if [[ "$ratio" -gt 30 ]]; then
                echo "  ⚠️ 修正系比率が30%を超えています（目標: 30%以下）"
            else
                echo "  ✅ 修正系比率は目標内"
            fi
        fi
    fi
}

# --- report: 週次改善レポート ---
cmd_report() {
    echo "=== 週次改善レポート ==="
    echo "生成日: $(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M')"
    echo ""

    cmd_status

    echo ""
    echo "=== 今週の改善履歴 ==="
    local history_file="$HOME/workspace-ai/nomuraya-agent-openclaw/moltbook/data/internal/improvement-history.jsonl"
    if [[ -f "$history_file" ]]; then
        local week_ago
        week_ago=$(date -v-7d -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -d "7 days ago" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
        jq -r "select(.ts >= \"$week_ago\") | \"[\(.ts)] \(.action // \"?\") - \(.result // \"?\")\"" "$history_file" 2>/dev/null \
            | head -20 || echo "  (履歴なし)"
    else
        echo "  (improvement-history.jsonl 未作成)"
    fi
}

# --- メイン ---
case "${1:-status}" in
    collect) cmd_collect ;;
    improve) shift; cmd_improve "$@" ;;
    status)  cmd_status ;;
    report)  cmd_report ;;
    *)
        echo "Usage: $0 {collect|improve|status|report}"
        exit 1
        ;;
esac
