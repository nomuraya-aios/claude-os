---
name: github-issue
description: GitHub Issueをdue date・クローズ要件付きで作成。
allowed-tools:
  - Bash
  - AskUserQuestion
---

# GitHub Issue 作成

タイトル・due date・クローズ要件を確認してから作成:

```bash
gh issue create --title "<タイトル>" --body "## クローズ要件

- [ ] {要件1}

due: YYYY-MM-DD"
```

- `due:` は行頭・`due: YYYY-MM-DD` 形式（ICS自動取り込み用）
- due不要なら本文から除外
- クローズ要件不明なら `- [ ] （記入してください）` を仮置き
