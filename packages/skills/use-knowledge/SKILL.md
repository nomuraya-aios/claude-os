---
name: use-knowledge
description: ナレッジDBから過去のWebFetch結果を検索。
allowed-tools: Grep, Read, Glob
---

# Use Knowledge Skill

## 目的

`~/ai-knowledge/webfetch/` ディレクトリから過去のWebFetch結果を検索・参照し、重複したWebFetchを避けてトークンを節約する。

---

## トリガーキーワード

- 「ナレッジ検索」
- 「過去のWebFetch」
- 「ナレッジ参照」
- 「/use-knowledge」
- 「以前調べた情報」

---

## 実施手順

### 1. ナレッジベース確認

まず、利用可能なナレッジファイルを確認：

```bash
find ~/ai-knowledge/webfetch -name "*.md" -type f | head -20
```

または、最新のファイルを確認：

```bash
ls -lt ~/ai-knowledge/webfetch/*/*.md | head -10
```

### 2. トピック検索

ユーザーに探したいトピックを質問し、該当するファイルを検索：

**ファイル名で検索**:
```bash
find ~/ai-knowledge/webfetch -name "*<topic>*.md"
```

**内容で検索（Grep）**:
```bash
grep -r "<キーワード>" ~/ai-knowledge/webfetch/ --include="*.md"
```

**例**:
- `find ~/ai-knowledge/webfetch -name "*jina*"`
- `grep -r "MCP" ~/ai-knowledge/webfetch/`

### 3. 内容参照

見つかったファイルを読み込んで要約：

```
Read ~/ai-knowledge/webfetch/YYYYmmdd/<topic>-HHMMSS.md
```

以下を確認：
- **取得日**: 情報の鮮度
- **元URL**: 元のソース
- **内容**: 保存されている情報

### 4. 関連ファイルの提案

見つかったファイルに関連する他のファイルがあれば提案：

```bash
# 同じ日付のファイル
ls ~/ai-knowledge/webfetch/YYYYmmdd/

# 類似トピック
find ~/ai-knowledge/webfetch -name "*<関連キーワード>*.md"
```

---

## WebFetch前のチェック

**重要**: 新しい情報を調べる前に、必ずこのナレッジベースを確認する習慣をつける

### チェックフロー

```
ユーザーがURL情報を要求
  ↓
use-knowledgeで既存情報を検索
  ↓
  ├─ 見つかった → 既存情報を提供（トークン節約）
  └─ 見つからない → Jina Reader経由でWebFetch → save-knowledge
```

---

## 使い方の例

### 例1: 特定トピックの検索

```
ユーザー: 「Jina Readerについて調べた情報ある？」
  ↓
find ~/ai-knowledge/webfetch -name "*jina*"
  ↓
見つかった: ~/ai-knowledge/webfetch/YYYYmmdd/jina-reader-HHMMSS.md
  ↓
内容を読み込んで要約
```

### 例2: キーワード検索

```
ユーザー: 「MCPに関する情報を探して」
  ↓
grep -r "MCP" ~/ai-knowledge/webfetch/ --include="*.md"
  ↓
複数ファイルが見つかった場合、リストアップして選択を促す
```

### 例3: 最新情報の確認

```
ユーザー: 「最近追加されたナレッジを教えて」
  ↓
ls -lt ~/ai-knowledge/webfetch/*/*.md | head -10
  ↓
最新10ファイルをリストアップ
```

---

## 出力形式

### 検索成功時

```
✅ ナレッジ検索結果

**見つかったファイル**: 2件

1. ~/ai-knowledge/webfetch/YYYYmmdd/jina-reader-HHMMSS.md
   - 取得日: 2025-12-29
   - トピック: Jina Reader
   - 元URL: https://github.com/jina-ai/reader

2. ~/ai-knowledge/webfetch/YYYYmmdd/claude-code-best-practices-HHMMSS.md
   - 取得日: 2025-12-25
   - トピック: Claude Code Best Practices
   - 元URL: https://anthropic.com/engineering/claude-code-best-practices

どのファイルを参照しますか？
```

### 検索失敗時

```
⚠️ ナレッジ検索結果

該当するファイルが見つかりませんでした。

**検索条件**: <キーワード>

新しくWebFetchしますか？
→ Yes: Jina Reader経由でWebFetch → save-knowledge
→ No: 検索キーワードを変更
```

---

## チェックリスト

実行前に確認：

- [ ] 既存ナレッジを検索したか
- [ ] 複数のキーワードで検索を試したか
- [ ] 見つかった情報の鮮度を確認したか
- [ ] 関連ファイルも確認したか

---

## トークン節約効果

過去のWebFetch結果を再利用することで、以下のトークンを節約：

| 操作 | トークン消費 |
|------|-------------|
| WebFetch（新規） | 約3,000-10,000トークン |
| Read（既存ナレッジ） | 約500-2,000トークン |
| **節約効果** | **約2,000-8,000トークン** |

---

## 自動化のヒント

セッション開始時に以下を習慣化：

```
このセッションでURLに関する情報が必要になった場合、
まず ~/ai-knowledge/webfetch/ を検索して既存情報がないか確認してください。
```
