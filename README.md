# claude-os

Claude Code用AI-OS。CLAUDE.md・skills・hooks・rulesを管理・配布する基盤。

## 構成

```
claude-os/
├── kernel/       CLAUDE.md・rules・hooks（OSコア）
├── packages/     skills・agents・modes（アプリ層）
├── bin/          aios CLI（パッケージ管理ツール）
└── deploy/       マシンへの展開スクリプト
```

## インストール

```bash
git clone git@github.com:nomuraya-aios/claude-os.git ~/workspace-ai/nomuraya-aios/claude-os
cd ~/workspace-ai/nomuraya-aios/claude-os
./deploy/install.sh
```

## パッケージ管理（予定）

```bash
aios install ocr        # skillをインストール
aios remove ocr
aios update             # 全パッケージ更新
aios list               # インストール済み一覧
aios deploy             # ~/.claude/ に展開
```

## 関連リポジトリ

- [aios-patterns](https://github.com/nomuraya-aios/aios-patterns) — 設計パターン集
- [claude-company-template](https://github.com/nomuraya-aios/claude-company-template) — プロジェクト適用テンプレート
