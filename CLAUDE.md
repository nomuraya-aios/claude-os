# claude-os

Claude Code用AI-OS。CLAUDE.md・skills・hooks・rulesの管理・配布・監視を行う運用基盤。

**オーナー**: nomuraya  
**リポジトリ**: `nomuraya-aios/claude-os`  
**ローカルパス**: `~/workspace-ai/nomuraya-aios/claude-os/`

---

## このリポジトリの使命

Claude Codeを「ツール」ではなく「OSとして振る舞う基盤」として管理する。
具体的には以下を担う：

| OSの概念 | claude-osでの実装 |
|---------|-----------------|
| カーネル | CLAUDE.md + rules + hooks |
| パッケージ管理 | aios CLI（install/remove/update） |
| ドライバー | MCPサーバー設定 |
| セキュリティ | 権限管理・secrets検出・banned-tools強制 |
| ヘルスチェック | システム監視・異常検知 |
| ロギング | セッションログ・トークン使用量追跡 |
| インストーラー | マシンへのワンコマンド展開 |
| アップデーター | 自動更新・バージョン管理・ロールバック |

---

## ディレクトリ構成と役割

```
claude-os/
├── kernel/          # OSコア（最優先・変更慎重）
│   ├── rules/       # ルール正本（banned-tools, git-rules等）
│   └── hooks/       # hookスクリプト正本
├── packages/        # アプリ層（インストール単位）
│   ├── skills/      # スキル（/ocr, /pdf等）
│   ├── agents/      # エージェント
│   └── modes/       # モード
├── bin/             # aios CLIツール
├── deploy/          # インストーラー・展開スクリプト
├── health/          # ヘルスチェック
├── logging/         # ロギングシステム
└── security/        # セキュリティ管理
```

---

## サブシステム責任範囲

### kernel/
- CLAUDE.md・rulesの正本を管理
- `~/.claude/` への反映は `deploy/sync.sh` 経由
- 直接編集禁止。PRレビュー必須

### packages/
- スキル・エージェント・モードのインストール単位
- 各パッケージは `manifest.yaml`（名前・バージョン・依存・インストール先）を持つ
- `aios install <name>` でインストール、`aios remove <name>` で削除

### bin/aios
- パッケージ管理CLI
- `install / remove / update / list / deploy / health` サブコマンド
- 実装言語: bash（依存なし・どのマシンでも動く）

### deploy/
- `install.sh`: 新規マシンへのフルセットアップ
- `sync.sh`: kernel変更を `~/.claude/` に反映
- `uninstall.sh`: 完全削除・ロールバック

### health/
- `health-check.sh`: システム全体の健全性確認
- チェック対象: hooks動作・必須ツール存在・settings.json・MCP接続
- 終了コード0=正常 / 1=警告 / 2=異常

### logging/
- トークン使用量・セッション数の集計
- 異常なトークン消費の検知・アラート
- ログフォーマット定義（既存 `~/.claude/logs/` との互換）

### security/
- secrets検出（APIキー・パスワードの誤コミット防止）
- banned-tools強制（rm -rf等の禁止コマンド検証）
- permissions.json管理（deny/allowリスト）

---

## 他リポジトリとの関係

```
aios-patterns        設計パターン集（参照元・上流知識）
    ↓ 参照
claude-os            実装・管理基盤（このリポジトリ）
    ↓ deploy/sync.sh
~/.claude/           実行環境（Claude Codeが実際に読む場所）
```

- `aios-patterns` は知識・レシピ置き場。claude-osはそれを実装する
- `claude-company-template` はプロジェクト適用のテンプレート。claude-osとは独立

---

## 開発ルール

- `kernel/` の変更は必ずPRを立てる（直接mainへのpush禁止）
- `packages/` の追加は `manifest.yaml` を必ず作成する
- スクリプトは `bash -n` で構文チェック後にcommit
- バージョンタグ: `v{major}.{minor}.{patch}` 形式

---

## 現在のステータス

- [ ] kernel: rules/hooks の正本移管
- [ ] packages/skills: 既存スキルの登録（ocr等）
- [ ] bin/aios: CLI実装
- [ ] deploy/install.sh: インストーラー実装
- [ ] health/health-check.sh: ヘルスチェック実装
- [ ] logging: トークン監視実装
- [ ] security: secrets検出実装
