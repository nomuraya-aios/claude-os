---
name: article
description: セッションログ/日報から記事作成。
---

# Article Skill - 記事作成

## 目的

セッションログや日報から記事を作成するフローを起動する。
記事化パイプライン（Flow B）のフェーズ2に対応。

**パイプライン仕様**: `~/ai-tasklogs/specs/article-pipeline-spec.yaml`

---

## トリガー

**発動キーワード**: `記事作成`, `記事化`, `記事を書く`, `記事を書こう`, `/article`

---

## 実行内容

### 1. 記事候補の確認

**引数あり**（例: `/article Issue #XX`）:
- 指定されたIssueまたはセッションログから記事化

**引数なし**:
- 直近のセッションログのフロントマターから `article_candidates` を検索
- 候補がある場合: 一覧を提示してユーザーに選択を求める
- 候補がない場合: ユーザーに記事テーマを確認

```bash
# 直近のセッションログから記事候補を検索
grep -r "article_candidates" ~/ai-tasklogs/sessions/$(date +%Y)/ --include="*.md" -l | head -5
```

### 2. 記事作成モードの読み込み

```
Read ~/.claude/modes/article-creation.md
```

**article-creation.md の内容**:
- 執筆前チェック（ターゲット読者、読者が得るもの、アクション）
- プラットフォーム確認（note / Zenn）
- 構成提案
- 本文生成
- 保存・コミット

### 3. 完了時の次ステップ案内

記事作成完了後、以下を提示:

```markdown
## 記事作成完了

**保存先**: <ファイルパス>

### 次のステップ

**サムネイル生成**（note.com投稿の場合）:
1. ベース画像生成: `uv run python src/generate_thumbnail.py`
2. テキスト合成: `uv run python src/overlay_text.py --title "タイトル" --subtitle "サブタイトル"`
   - 元画像（thumbnail.png）は変更されない
   - リテイク時は --title / --subtitle を変えて再実行
   - 出力: thumbnail_text.png

**公開前レビュー**:
→ `/review <ファイルパス>` でレビューを開始
（外部リンクが含まれる場合、原典照合を自動実施）
```

---

## フロー全体における位置づけ

```
/summary → セッションログ作成 + 記事候補自動判定
    ↓
/article → 記事作成（← 今ここ）
    ↓
/review  → 記事レビュー（センシティブ・書き味・構成）
    ↓
/publish → 投稿（Zenn: git push / note: 手動）
```

---

## 使用例

```bash
# 記事候補から記事化
/article

# 特定のIssueから記事化
/article Issue #123

# セッションログから直接記事化
/article ~/ai-tasklogs/sessions/2026/02/08/claude-code-pipeline-design.md
```

---

## 関連ファイル

| 用途 | パス |
|------|------|
| パイプライン仕様（SSOT） | `~/ai-tasklogs/specs/article-pipeline-spec.yaml` |
| 記事作成モード | `~/.claude/modes/article-creation.md` |
| 品質基準 | `~/.claude/rules/writing-quality.md` |
| レビュースキル | `~/.claude/skills/review/SKILL.md` |
| 投稿スキル | `~/.claude/skills/publish/SKILL.md` |

---

## メンテナンス

**導線管理**: このスキルは以下から参照される
- CLAUDE.md の「自動トリガースキル」セクション
- `~/.claude/modes/thread-summary.md` の「記事候補の自動判定」セクション

**更新時の注意**:
- 記事作成の詳細手順は `article-creation.md` で管理（このファイルでは行わない）
- パイプライン仕様の変更は `article-pipeline-spec.yaml` で行う
