# leverageAI-OS

Claude Code 用 AI-OS。`~/.claude/` の設定（rules・hooks・skills）をパッケージとして管理・配布する基盤。

**ミッション:** LLM を適切に運用し、トークン管理を徹底する。

## クイックスタート

```bash
curl -fsSL https://raw.githubusercontent.com/nomuraya-aios/claude-os/main/deploy/install.sh | bash
```

または手動で:

```bash
git clone https://github.com/nomuraya-aios/claude-os.git ~/.local/share/claude-os/repo
cd ~/.local/share/claude-os/repo
bash deploy/install.sh
```

インストール後に `aios health` で環境確認。

## aios コマンド

```bash
aios install <name>       # スキルをインストール
aios remove <name>        # スキルを削除
aios list                 # スキル一覧（--installed で導入済みのみ）
aios deploy               # kernel を ~/.claude/ にマージ
aios sync-personal        # personal リポジトリを ~/.claude/ にマージ
aios health               # 環境ヘルスチェック
aios version              # バージョン確認
```

## 利用可能なスキル

| スキル | 説明 | 依存 |
|--------|------|------|
| ocr | NDLOCR-Lite 日本語OCR | ndlocr-lite, uv |
| pdf | PDF読み取り・要約 | — |
| tts | テキスト音声読み上げ | — |
| transcribe-diarize | 音声文字起こし・話者分離 | uv |
| github-issue | GitHub Issue作成 | gh |
| article | 記事執筆・ブログ投稿 | — |
| web-fetch | URL取得・要約 | — |
| pptx | PowerPoint作成 | uv |
| use-knowledge | 保存ナレッジ参照 | — |

## kernel（OSコア）

インストール時に `~/.claude/` へ追加マージされる共通設定:

- `kernel/rules/no-llm-autonomous-loop.md` — LLMループ禁止
- `kernel/rules/no-anthropic-api-background.md` — BG Anthropic API 禁止
- `kernel/rules/token-explosion-prevention.md` — トークン爆発3類型と防止策
- `kernel/hooks/pre-bash-rm-rf-block.sh` — `rm -rf` ブロック hook
- `kernel/hooks/pre-bash-no-verify-block.sh` — `--no-verify` ブロック hook

**重要:** `aios deploy` は既存の `~/.claude/` 設定を上書きしません。新規ファイルの追加のみ行います（`--force` で上書き可）。

## personal-os パターン

自分の設定（rules/hooks）を別リポジトリで管理して claude-os の上に重ねる方法:

```bash
# config/aios.config.yaml を作成
cp config/aios.config.yaml.example config/aios.config.yaml
# personal_repo のパスを編集

# personal リポジトリを同期
aios sync-personal
```

`aios deploy`（claude-os 共通設定）→ `aios sync-personal`（個人設定）の順で実行することで、共通ルールの上に個人設定を重ねられます。

## リポジトリ構成

```
claude-os/
├── bin/aios              CLI エントリポイント
├── kernel/
│   ├── rules/            配布するルールファイル
│   └── hooks/            配布する hook スクリプト
├── packages/
│   ├── manifest.yaml     パッケージ定義
│   └── skills/           スキル実体
├── config/
│   └── budget.yaml       トークンバジェット設定
├── deploy/
│   ├── install.sh        ワンコマンドセットアップ
│   ├── sync.sh           kernel → ~/.claude/ マージ
│   ├── sync-personal.sh  personal repo → ~/.claude/ マージ
│   └── uninstall.sh      削除
├── health/health-check.sh
├── security/
│   ├── banned-tools.yaml
│   ├── audit.sh
│   └── pre-commit-check.sh
├── budget/               トークンバジェット管理
├── breaker/              サーキットブレーカー
├── logging/              LLM呼び出しログ
├── meter/                トークン集計
└── registry/             プロセス登録
```

## 関連リポジトリ

- [aios-patterns](https://github.com/nomuraya-aios/aios-patterns) — 設計パターン集
- [claude-company-template](https://github.com/nomuraya-aios/claude-company-template) — プロジェクト適用テンプレート
