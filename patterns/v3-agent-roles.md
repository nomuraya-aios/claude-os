# v3-agent-roles — エージェント責務マップ

**最終更新**: 2026-04-15

エージェント・背景ジョブの責務・実行タイミング・入力出力を定義。

---

## エージェント一覧

| エージェント | 責務 | 実行タイミング | 入力 | 出力 |
|------------|------|--------------|------|------|
| **agent-doc-auditor** | ドキュメント乖離検出 | 毎週月曜 06:00 JST | git log + .md ファイル | feedback.jsonl (scope: "documentation") |
| SessionLogAgent | セッション開始ログ作成 | セッション開始時 | CLI args | ~/ai-tasklogs/sessions/{date}/{ID}.md |
| DailyReportAgent | 日報生成 | 毎日 09:30 JST | セッションログ一覧 | ~/ai-tasklogs/reports/{date}.md |
| agent-system-improver | フィードバック処理 | 毎週木曜 19:00 JST | feedback.jsonl | パッチ提案 + PR作成 |

---

## agent-doc-auditor 詳細

**目的**: git log と .md ファイルの更新日を突合し、実装の変更にドキュメントが追従できていない乖離を検出。

**実行周期**: 毎週月曜 06:00 JST （launchd: ai.aios.agent-doc-auditor.plist）

**スクリプト**: `packages/agents/agent-doc-auditor.sh`

**検出ロジック**:

| 検出方式 | 内容 | NG判定基準 |
|--------|------|----------|
| deprecated-terms 照合 | `.md` 内に廃止パターンが残っていないか | `deprecated-terms.txt` のいずれかがヒット |
| ファイルパス検証 | `.md` に記載されたパスが実装に存在するか | `ls` で存在しないパスを検出 |
| git 乖離検出 | 実装ファイルの更新日 > .md の更新日 | 30日以内の git log 対象ファイルが .md に記載されており、.md の方が古い |

**出力**: `~/.claude/engineering-feedback/feedback.jsonl` に以下形式で投入

```json
{
  "timestamp": "2026-04-15T06:00:00Z",
  "doc_path": "path/to/doc.md",
  "scope": "documentation",
  "severity": "warning",
  "issue": "Found deprecated term: 'claude -p'",
  "suggestion": "Review and update to current implementation pattern",
  "automated_by": "agent-doc-auditor"
}
```

**トークン爆発リスク**: なし（LLM呼び出しなし、shell grep/git のみ）

**制御フロー**:
- `--dry-run`: 検出結果を stdout に出力するが feedback.jsonl に投入しない
- デフォルト: feedback.jsonl に投入

---

## 将来の拡張

- **agent-doc-auditor**: 複数リポジトリ横断スキャン対応
- **agent-system-improver**: feedback.jsonl から自動パッチ生成・PR作成
- **doc-llm-first**: hook化で提出前ドキュメントチェック自動化

---

## 関連ファイル

| ファイル | 用途 |
|---------|------|
| `packages/agents/agent-doc-auditor.sh` | 実装 |
| `packages/agents/deprecated-terms.txt` | 廃止パターン管理（外部ファイル） |
| `packages/agents/launchd/ai.aios.agent-doc-auditor.plist` | launchd 登録用 |
| `~/.claude/rules/doc-llm-first.md` | LLMファースト基準 |
| `~/.claude/skills/doc-review/SKILL.md` | 対話的チェック用スキル |
