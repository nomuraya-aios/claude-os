---
name: web-fetch
description: Jina Reader経由でWebコンテンツ取得。
allowed-tools: WebFetch
---

# Web Fetch

## 手順
1. **data-hub確認**（重複防止）: `bash ~/.claude/scripts/search-data-hub.sh --url "<URL>"` → ヒットしたら返却してWebFetchスキップ
2. **例外**: API(`/api/`, `.json`)・localhost・バイナリ(`.jpg/.png/.pdf/.mp4/.zip`) → 素のURL使用
3. **実行**: 全URLに `https://r.jina.ai/` プレフィックス付けてWebFetch
4. **保存**: PostToolUse hookが自動でdata-hub登録（手動操作不要）

デフォルトプロンプト: 「このページの内容を日本語で要約してください」
Jina Readerエラー時: 素URLでのリトライを提案
