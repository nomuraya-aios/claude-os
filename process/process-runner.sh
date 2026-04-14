#!/bin/bash
# process/process-runner.sh
#
# 目的:
#   claude-os の Issueドリブンプロセス管理。
#   spawn→exec→running→exit→reap のライフサイクルを管理する。
#   設計詳細: docs/process-lifecycle.md
#
# 安全設計:
#   - 再試行なし（失敗は人間が確認してから手動再実行）
#   - プロセス全体タイムアウト: PROCESS_TIMEOUT秒（デフォルト600秒）
#   - oh-dispatch max-turns: MAX_TURNS（デフォルト20）
#   - 終了コードに基づく厳密なステータス遷移
#
# 使用方法:
#   bash process-runner.sh --repo <owner/repo> --issue <number>
#   bash process-runner.sh --repo <owner/repo> --issue <number> --dry-run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AIOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="${AIOS_STATE_DIR:-$HOME/.local/share/claude-os/state}"
PROCESS_TABLE="$STATE_DIR/process-table.jsonl"
PROCESSED_FILE="$STATE_DIR/processed.txt"

# 設定
PROCESS_TIMEOUT="${PROCESS_TIMEOUT:-600}"   # 秒
MAX_TURNS="${MAX_TURNS:-20}"                 # oh-dispatch ターン上限
DRY_RUN=0

mlog() { echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%dT%H:%M:%S')] [ProcessRunner] $*"; }

# --- 引数解析 ---
REPO=""
ISSUE_NUMBER=""
while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --repo)      shift; REPO="${1:-}" ;;
    --issue)     shift; ISSUE_NUMBER="${1:-}" ;;
    --dry-run)   DRY_RUN=1 ;;
    --timeout)   shift; PROCESS_TIMEOUT="${1:-600}" ;;
    --max-turns) shift; MAX_TURNS="${1:-20}" ;;
  esac
  shift
done

if [[ -z "$REPO" || -z "$ISSUE_NUMBER" ]]; then
  echo "使用方法: $0 --repo <owner/repo> --issue <number> [--dry-run]" >&2
  exit 1
fi

PROCESS_ID="${REPO}:${ISSUE_NUMBER}"

# --- 状態ディレクトリ初期化 ---
mkdir -p "$STATE_DIR"
touch "$PROCESS_TABLE" "$PROCESSED_FILE"

# --- ユーティリティ ---

# プロセステーブルへの書き込み（flock使用）
table_write() {
  local json="$1"
  (
    flock -x 200
    echo "$json" >> "$PROCESS_TABLE"
  ) 200>"${PROCESS_TABLE}.lock"
}

# プロセステーブルのステータス更新
table_update_status() {
  local target_id="$1"
  local new_status="$2"
  local extra="${3:-}"
  local now
  now=$(TZ=UTC date '+%Y-%m-%dT%H:%M:%SZ')
  local tmp="${PROCESS_TABLE}.tmp.$$"

  (
    flock -x 200
    while IFS= read -r line; do
      local line_id
      line_id=$(echo "$line" | jq -r '.id // ""')
      if [[ "$line_id" == "$target_id" ]]; then
        local updated
        updated=$(echo "$line" | jq -c \
          --arg s "$new_status" --arg t "$now" \
          '. + {status: $s, updated_at: $t}')
        if [[ -n "$extra" ]]; then
          updated=$(echo "$updated" | jq -c ". + $extra")
        fi
        echo "$updated"
      else
        echo "$line"
      fi
    done < "$PROCESS_TABLE" > "$tmp"
    mv "$tmp" "$PROCESS_TABLE"
  ) 200>"${PROCESS_TABLE}.lock"
}

# GitHubラベル操作
label_set() {
  local remove_label="${1:-}"
  local add_label="${2:-}"
  [[ "$DRY_RUN" -eq 1 ]] && { mlog "[DRY-RUN] label: -$remove_label +$add_label"; return 0; }
  [[ -n "$remove_label" ]] && gh issue edit "$ISSUE_NUMBER" --repo "$REPO" \
    --remove-label "$remove_label" 2>/dev/null || true
  [[ -n "$add_label" ]] && gh issue edit "$ISSUE_NUMBER" --repo "$REPO" \
    --add-label "$add_label" 2>/dev/null || true
}

# Issueコメント
issue_comment() {
  local body="$1"
  [[ "$DRY_RUN" -eq 1 ]] && { mlog "[DRY-RUN] comment: $body"; return 0; }
  gh issue comment "$ISSUE_NUMBER" --repo "$REPO" --body "$body"
}

# ラベル確認・作成（初回のみ）
ensure_labels() {
  local labels=("status:queued" "status:running" "status:done" "status:failed" "status:timeout")
  for label in "${labels[@]}"; do
    gh label list --repo "$REPO" --json name -q '.[].name' 2>/dev/null | grep -qx "$label" || \
      gh label create "$label" --repo "$REPO" --color "ededed" 2>/dev/null || true
  done
}

# --- 冪等性チェック ---
check_already_processed() {
  if grep -qxF "$PROCESS_ID" "$PROCESSED_FILE" 2>/dev/null; then
    mlog "処理済みスキップ: $PROCESS_ID"
    exit 0
  fi
}

# --- 二重起動チェック ---
check_already_running() {
  if grep -q "\"id\":\"$PROCESS_ID\".*\"status\":\"running\"" "$PROCESS_TABLE" 2>/dev/null; then
    mlog "実行中スキップ（二重起動防止）: $PROCESS_ID"
    exit 0
  fi
}

# --- タイムアウト中断処理 ---
handle_timeout() {
  mlog "タイムアウト: $PROCESS_ID (${PROCESS_TIMEOUT}秒超過)"
  # ハンドラのプロセスグループ全体をkill（孤児プロセス残留防止）
  if [[ -n "${HANDLER_PGID:-}" ]]; then
    kill -TERM -"$HANDLER_PGID" 2>/dev/null || true
    sleep 2
    kill -KILL -"$HANDLER_PGID" 2>/dev/null || true
  fi
  table_update_status "$PROCESS_ID" "timeout" '{"exit_code": 124}'
  label_set "status:running" "status:timeout"
  issue_comment "⏰ タイムアウト (${PROCESS_TIMEOUT}秒超過)

自動再試行はしません。内容を確認してから手動で再実行してください。
\`\`\`
bash process/process-runner.sh --repo $REPO --issue $ISSUE_NUMBER
\`\`\`"
  exit 124
}

trap handle_timeout ALRM

# --- 起動時の残骸プロセスクリーンアップ ---
# 前回のprocess-runnerが異常終了してrunningのまま残っているエントリを検出してreap
cleanup_stale_processes() {
  [[ ! -f "$PROCESS_TABLE" ]] && return 0

  local now_epoch
  now_epoch=$(date +%s)
  local tmp="${PROCESS_TABLE}.tmp.$$"
  local cleaned=0

  (
    flock -x 200
    while IFS= read -r line; do
      local status pid started_at timeout_val id
      status=$(echo "$line" | jq -r '.status // ""')
      pid=$(echo "$line" | jq -r '.pid // ""')
      started_at=$(echo "$line" | jq -r '.started_at // ""')
      timeout_val=$(echo "$line" | jq -r '.max_timeout // 600')
      id=$(echo "$line" | jq -r '.id // ""')

      if [[ "$status" == "running" ]]; then
        # PIDが実際に生きているか確認
        local pid_alive=0
        [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && pid_alive=1

        # 開始時刻からtimeout_val秒以上経過しているか確認
        local elapsed=0
        if [[ -n "$started_at" ]]; then
          local start_epoch
          start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" +%s 2>/dev/null \
            || date -d "$started_at" +%s 2>/dev/null || echo "0")
          elapsed=$(( now_epoch - start_epoch ))
        fi

        if [[ "$pid_alive" -eq 0 || "$elapsed" -gt "$timeout_val" ]]; then
          mlog "残骸プロセス検出 → タイムアウト扱いでreap: $id (pid=$pid, elapsed=${elapsed}s)"
          echo "$line" | jq -c \
            --arg s "timeout" --arg t "$(TZ=UTC date '+%Y-%m-%dT%H:%M:%SZ')" \
            '. + {status: $s, updated_at: $t, stale_cleanup: true}'
          cleaned=$((cleaned + 1))
          continue
        fi
      fi
      echo "$line"
    done < "$PROCESS_TABLE" > "$tmp"
    mv "$tmp" "$PROCESS_TABLE"
  ) 200>"${PROCESS_TABLE}.lock"

  [[ "$cleaned" -gt 0 ]] && mlog "残骸クリーンアップ完了: ${cleaned}件"
  return 0
}

# --- ハンドラ解決 ---
# handler-{label}.sh または handler-default.sh を探す
resolve_handler() {
  local labels
  labels=$(gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json labels -q '.labels[].name' 2>/dev/null || echo "")

  for label in $labels; do
    local handler="$AIOS_ROOT/process/handlers/handler-${label//:/--}.sh"
    if [[ -f "$handler" ]]; then
      echo "$handler"
      return 0
    fi
  done

  # デフォルトハンドラ
  local default_handler="$AIOS_ROOT/process/handlers/handler-default.sh"
  if [[ -f "$default_handler" ]]; then
    echo "$default_handler"
    return 0
  fi

  echo ""
}

# --- reap: 正常終了 ---
reap_success() {
  local result_summary="${1:-処理完了}"
  mlog "正常終了: $PROCESS_ID"
  table_update_status "$PROCESS_ID" "done" '{"exit_code": 0}'
  echo "$PROCESS_ID" >> "$PROCESSED_FILE"
  label_set "status:running" "status:done"
  issue_comment "✅ 完了

$result_summary"
  [[ "$DRY_RUN" -eq 0 ]] && gh issue close "$ISSUE_NUMBER" --repo "$REPO" || true
}

# --- reap: スキップ ---
reap_skip() {
  mlog "スキップ: $PROCESS_ID"
  table_update_status "$PROCESS_ID" "done" '{"exit_code": 20, "reason": "skipped"}'
  echo "$PROCESS_ID" >> "$PROCESSED_FILE"
  label_set "status:running" "status:done"
  [[ "$DRY_RUN" -eq 0 ]] && gh issue close "$ISSUE_NUMBER" --repo "$REPO" || true
}

# --- reap: 失敗 ---
reap_failure() {
  local exit_code="$1"
  local error_log="${2:-}"
  mlog "失敗: $PROCESS_ID (exit $exit_code)"
  table_update_status "$PROCESS_ID" "failed" "{\"exit_code\": $exit_code}"
  label_set "status:running" "status:failed"
  issue_comment "❌ 失敗 (exit: $exit_code)

${error_log}

⚠️ 自動再試行はしません。内容を確認してから手動で再実行してください。
\`\`\`
bash process/process-runner.sh --repo $REPO --issue $ISSUE_NUMBER
\`\`\`"
}

# ===== メイン処理 =====

mlog "開始: $PROCESS_ID (timeout=${PROCESS_TIMEOUT}s, max-turns=${MAX_TURNS})"

# 起動時に残骸プロセスをクリーンアップ
cleanup_stale_processes

check_already_processed
check_already_running

# ラベル確認
ensure_labels

# Issueの状態確認
ISSUE_STATE=$(gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")
if [[ "$ISSUE_STATE" == "CLOSED" ]]; then
  mlog "クローズ済みスキップ: $PROCESS_ID"
  exit 0
fi

# spawn: プロセステーブルに登録
STARTED_AT=$(TZ=UTC date '+%Y-%m-%dT%H:%M:%SZ')
table_write "$(jq -cn \
  --arg id "$PROCESS_ID" \
  --arg repo "$REPO" \
  --argjson issue "$ISSUE_NUMBER" \
  --argjson pid $$ \
  --arg started_at "$STARTED_AT" \
  --argjson timeout "$PROCESS_TIMEOUT" \
  '{id: $id, repo: $repo, issue: $issue, pid: $pid, started_at: $started_at, status: "running", max_timeout: $timeout}')"

# exec: ラベル更新
label_set "status:queued" "status:running"

# ハンドラ解決
HANDLER=$(resolve_handler)
if [[ -z "$HANDLER" ]]; then
  mlog "ハンドラなし（スキップ）: $PROCESS_ID"
  reap_skip
  exit 0
fi

mlog "ハンドラ: $HANDLER"

# --- budget / breaker チェック（ハンドラ実行前）---
BREAKER_CHECK="$AIOS_ROOT/breaker/breaker-check.sh"
BUDGET_CHECK="$AIOS_ROOT/budget/budget-check.sh"

if [[ -f "$BREAKER_CHECK" ]]; then
  if ! bash "$BREAKER_CHECK" 2>&1; then
    mlog "サーキットブレーカーOPEN: $PROCESS_ID — 実行をブロック"
    table_update_status "$PROCESS_ID" "failed" '{"exit_code": 2, "reason": "breaker_open"}'
    label_set "status:running" "status:failed"
    issue_comment "🔴 サーキットブレーカーがOPENのため実行をブロックしました。

\`breaker-reset.sh\` でリセット後に再実行してください。"
    exit 2
  fi
fi

if [[ -f "$BUDGET_CHECK" ]]; then
  if ! bash "$BUDGET_CHECK" --tokens "${EXPECTED_TOKENS:-5000}" --type "issue-handler" 2>&1; then
    mlog "budget上限超過: $PROCESS_ID — 実行をブロック"
    table_update_status "$PROCESS_ID" "failed" '{"exit_code": 1, "reason": "budget_exceeded"}'
    label_set "status:running" "status:failed"
    issue_comment "🔴 budget上限超過のため実行をブロックしました。

明日以降またはbudget上限を引き上げてから再実行してください。"
    exit 1
  fi
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  mlog "[DRY-RUN] ハンドラ実行をスキップ"
  reap_success "ドライラン完了"
  exit 10
fi

# running: プロセスグループごとkillできるようsetsidで起動
EXIT_CODE=0
HANDLER_PGID=""

set +e
# setsid で新しいプロセスグループを作成し、PGIDを記録
# タイムアウト時に PGID全体をkillして孫プロセスの残留を防ぐ
OUTPUT=$(setsid bash "$HANDLER" \
  --repo "$REPO" \
  --issue "$ISSUE_NUMBER" \
  --max-turns "$MAX_TURNS" 2>&1 &
HANDLER_PID=$!
HANDLER_PGID=$(ps -o pgid= -p "$HANDLER_PID" 2>/dev/null | tr -d ' ' || echo "")
# タイムアウト監視
( sleep "$PROCESS_TIMEOUT" && kill -ALRM $$ 2>/dev/null ) &
WATCHDOG_PID=$!
wait "$HANDLER_PID"
EXIT_CODE_INNER=$?
kill "$WATCHDOG_PID" 2>/dev/null || true
exit "$EXIT_CODE_INNER"
)
EXIT_CODE=$?
set -e

# exit: 終了コードに基づくreap
case "$EXIT_CODE" in
  0)
    reap_success "$OUTPUT"
    ;;
  10)
    # ドライラン完了（Issueはオープンのまま）
    table_update_status "$PROCESS_ID" "done" '{"exit_code": 10}'
    echo "$PROCESS_ID" >> "$PROCESSED_FILE"
    label_set "status:running" "status:done"
    mlog "ドライラン完了: $PROCESS_ID"
    ;;
  20)
    reap_skip
    ;;
  124)
    handle_timeout
    ;;
  *)
    reap_failure "$EXIT_CODE" "$OUTPUT"
    ;;
esac

mlog "完了: $PROCESS_ID (exit $EXIT_CODE)"
exit "$EXIT_CODE"
