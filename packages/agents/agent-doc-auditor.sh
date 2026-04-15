#!/bin/bash
#
# agent-doc-auditor.sh — Documentation乖離検出エージェント
#
# 目的: 週1回実行され、git log と doc 更新日を突合して乖離を検出。
#       問題は feedback.jsonl に scope: "documentation" で投入。
#
# 実行タイミング: launchd（毎週月曜 06:00 JST）
# トークン爆発リスク: LLM呼び出しなし（shell grep/git のみ）
#
# 使用方法:
#   ./agent-doc-auditor.sh                # 本番実行（feedback.jsonl に投入）
#   ./agent-doc-auditor.sh --dry-run      # ドライラン（投入せず標準出力のみ）
#

set -euo pipefail

# ===== 設定 =====
REPO_ROOT="${1:-.}"
DRY_RUN="${2:-}"
DEPRECATED_TERMS_FILE="$(dirname "$0")/deprecated-terms.txt"
FEEDBACK_FILE="${HOME}/.claude/engineering-feedback/feedback.jsonl"
SCRIPT_NAME="$(basename "$0")"

# ===== ヘルパー関数 =====

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >&2
}

# feedback.jsonl に投入（ドライラン時はスキップ）
add_feedback() {
  local doc_path="$1"
  local issue="$2"
  local suggestion="$3"

  if [ "$DRY_RUN" = "--dry-run" ]; then
    echo "  [DRY-RUN] Would add feedback: $doc_path"
    return
  fi

  # ~/.claude/engineering-feedback/ が存在しなければ作成
  mkdir -p "$(dirname "$FEEDBACK_FILE")"

  jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg doc_path "$doc_path" \
    --arg scope "documentation" \
    --arg severity "warning" \
    --arg issue "$issue" \
    --arg suggestion "$suggestion" \
    '{
      timestamp: $timestamp,
      doc_path: $doc_path,
      scope: $scope,
      severity: $severity,
      issue: $issue,
      suggestion: $suggestion,
      automated_by: "agent-doc-auditor"
    }' >> "$FEEDBACK_FILE"

  log "✓ Feedback added: $doc_path"
}

# ===== 検出ロジック =====

check_deprecated_terms() {
  local doc_path="$1"

  if [ ! -f "$DEPRECATED_TERMS_FILE" ]; then
    log "⚠️  deprecated-terms.txt not found: $DEPRECATED_TERMS_FILE"
    return
  fi

  # deprecated-terms.txt から1行ずつ読んで grep
  while IFS= read -r term; do
    [ -z "$term" ] && continue  # 空行スキップ

    if grep -q -F "$term" "$doc_path" 2>/dev/null; then
      log "⚠️  Found deprecated term: $term in $doc_path"
      add_feedback \
        "$doc_path" \
        "Deprecated term found: '$term'" \
        "Review and update to current implementation pattern"
    fi
  done < "$DEPRECATED_TERMS_FILE"
}

check_missing_paths() {
  local doc_path="$1"

  # ドキュメント内のパス記述を抽出（行頭の /, ~, $ から始まるもの）
  # 簡易パターン: ~/ , $HOME 形式
  grep -oE '(~|/[a-zA-Z0-9_\-./]+ )|(\\$[A-Z_]+)' "$doc_path" 2>/dev/null | while read -r path_pattern; do
    # 実際のパスに展開
    expanded_path="${path_pattern/\~/$HOME}"

    # 末尾の空白を削除
    expanded_path="${expanded_path% }"

    # パスが存在するか確認（存在しないなら NG）
    if [ -n "$expanded_path" ] && ! [ -e "$expanded_path" ]; then
      log "⚠️  Path does not exist: $expanded_path (in $doc_path)"
      add_feedback \
        "$doc_path" \
        "Reference to non-existent path: $expanded_path" \
        "Verify path exists or is correct. Update if implementation changed."
    fi
  done
}

check_git_divergence() {
  local doc_path="$1"
  local doc_mtime

  doc_mtime=$(stat -f %m "$doc_path" 2>/dev/null || stat -c %Y "$doc_path" 2>/dev/null)

  # git log で 30日以内に変更されたスクリプト・設定ファイルを取得
  # ドキュメント内に記載されているスクリプト名が変更されていないかチェック

  # 簡易版: git log の対象ファイルを正規表現で抽出
  cd "$REPO_ROOT" || return

  git log --oneline --since="30 days ago" --name-only 2>/dev/null | \
    grep -v ".md$" | \
    grep -v "^$" | \
    sort -u | while read -r impl_file; do

      # ファイル名がドキュメント内に記載されているか確認
      if grep -q "$(basename "$impl_file")" "$doc_path" 2>/dev/null; then
        impl_mtime=$(git log -1 --format=%cI -- "$impl_file" 2>/dev/null | date +%s -f -)

        # ドキュメントの更新日が実装より古い場合は乖離の可能性
        if [ "$impl_mtime" -gt "$doc_mtime" ] 2>/dev/null; then
          log "⚠️  Potential divergence: $impl_file updated after $doc_path"
          add_feedback \
            "$doc_path" \
            "Implementation file ($impl_file) modified after documentation update" \
            "Review documentation to ensure it reflects current implementation"
        fi
      fi
    done
}

# ===== メイン処理 =====

main() {
  log "Starting agent-doc-auditor in $(pwd)"

  [ -d "$REPO_ROOT" ] || {
    log "❌ Repository directory not found: $REPO_ROOT"
    exit 1
  }

  cd "$REPO_ROOT" || exit 1

  # .md ファイルを列挙
  mapfile -t doc_files < <(find . -name "*.md" -type f -not -path "./.git/*" 2>/dev/null | head -50)

  if [ ${#doc_files[@]} -eq 0 ]; then
    log "No .md files found"
    exit 0
  fi

  log "Found ${#doc_files[@]} documentation files"

  # 各ドキュメントについて3つのチェック
  for doc_file in "${doc_files[@]}"; do
    log "Checking: $doc_file"

    check_deprecated_terms "$doc_file"
    check_missing_paths "$doc_file"
    check_git_divergence "$doc_file"
  done

  log "✓ Audit complete"
}

# ドライランモード確認
if [ "$DRY_RUN" = "--dry-run" ]; then
  log "Running in DRY-RUN mode (no feedback.jsonl updates)"
  log ""
fi

main "$@"
