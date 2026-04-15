# SPEC — LLMファーストドキュメンテーション整備システム

**作成日**: 2026-04-15 22:20 JST
**担当モデル**: Sonnet 4.6（設計）→ 次セッション（実装）

## 背景・目的

ドキュメンテーション作業で「書いた = 完了」になりやすく、以下が毎回抜け落ちる：
- LLMが読んで正しく動ける構造になっているか
- 実装との乖離が生じていないか
- いつ見直すかが定義されているか

今回 moltbook で実際に発生した問題（Groq優先・Ollama廃止・claude-p廃止が複数ファイルに残存）を
サブエージェントの調査で初めて発見したことが直接の契機。
書くだけでなく「LLMが使える状態を継続的に保つ」仕組みを3層で実装する。

## スコープ（実装する範囲）

### Layer 1: グローバルルール
- `~/.claude/rules/doc-llm-first.md` を新規作成
- ドキュメント作成・修正時のマインドセットと4軸チェックリストを定義
- CLAUDE.md への参照追加（`@~/.claude/rules/doc-llm-first.md` を core-behaviors.md 経由で読み込む）

### Layer 2: /doc-review スキル
- `~/.claude/skills/doc-review/SKILL.md` を新規作成
- 対象ドキュメントを受け取り4軸で品質チェックし、問題を feedback.jsonl に投入する
- `~/workspace-ai/nomuraya-aios/claude-os/packages/skills/doc-review/SKILL.md` にも同内容を配置
- `manifest.yaml` にエントリ追加
- `~/.claude/CLAUDE.md` のスキルトリガー一覧に追記

### Layer 3: agent-doc-auditor.sh
- `~/workspace-ai/nomuraya-aios/claude-os/packages/agents/agent-doc-auditor.sh` を新規作成
- 週1回（毎週月曜 06:00 JST）、git log と doc 更新日を突合して乖離を検出
- 問題は `~/.claude/engineering-feedback/feedback.jsonl` に `scope: "documentation"` で投入
- launchd plist `ai.aios.agent-doc-auditor.plist` を新規作成
- v3-agent-roles.md にエントリ追加

## スコープ外（やらないこと）

- ドキュメント自動修正（検出のみ。修正は人間またはagent-system-improverが行う）
- 全プロジェクト横断の一括スキャン（対象は git 管理下の .md ファイルのみ）
- フロントマター自動挿入 hook（Layer 1 のルールのみで対応、hook 化は将来対応）
- ドキュメント生成（既存の /article スキルで対応）

## 実装方針

### Layer 1 — doc-llm-first.md の構造

```
## LLMファーストドキュメントの4軸チェック

### 軸1: 判断可能か
LLMがこれを読んで次の行動を決められるか。
- NG: 「詳細は別ファイル参照」のみで終わる
- OK: 判断に必要な情報が自己完結しているか、参照先が明示されている

### 軸2: 実装と突合できるか
ファイルパス・コマンド・フラグ・スクリプト名が現在の実装と一致するか。
- 確認方法: ドキュメント内のファイルパスが実際に存在するか grep/ls で確認する

### 軸3: 更新トリガーが定義されているか
「いつ見直すか」が書いてあるか。
- NG: 更新日だけある（「最終更新: 2026-04-01」）
- OK: 「実装変更時」「30日毎」「OR paid キー変更時」など条件が書いてある

### 軸4: 陳腐化サインが検出できるか
廃止済みスクリプト名・古いフォールバック順・存在しないファイルパスを
機械的に発見できる構造になっているか。
- コマンド例・ファイルパス・スクリプト名は grep で突合可能な形で書く
```

### Layer 2 — /doc-review スキルの処理フロー

```
1. 引数からドキュメントパスを取得（なければカレントディレクトリの .md を列挙）
2. ドキュメントを Read
3. 4軸チェックを実施（LLMが直接評価）
4. 各軸をスコア（OK/WARNING/NG）と理由で記録
5. WARNING/NG があれば修正案を提示
6. NG が1件以上あれば feedback.jsonl に投入
7. 結果をテーブル形式で出力
```

スコア判定基準:
- OK: 問題なし
- WARNING: 改善推奨（動作には支障ないが将来的に陳腐化リスク）
- NG: 即修正が必要（LLMが誤動作する・実装と乖離している）

### Layer 3 — agent-doc-auditor.sh の検出ロジック

```bash
# 突合方法（順に実行）
# git log で直近30日に変更されたスクリプト・設定ファイルを取得
# 同リポジトリ内の .md ファイルを走査
# .md 内に変更されたファイル名が言及されている場合、
#    .md の更新日がそのファイルの更新日より古ければ「乖離」と判定
# .md 内のコマンド・ファイルパスが実際に存在するかチェック（grep + ls）
# 廃止パターン一覧（deprecated-terms.txt）との照合
```

廃止パターン一覧（deprecated-terms.txt）の初期内容:
- `claude -p`（バックグラウンド用途。generateモードの限定復活は除外）
- `Groq優先`
- `Ollama（captcha優先）`
- `claude_p プロバイダー`

### ファイル構成

```
~/.claude/
├── rules/
│   └── doc-llm-first.md          # Layer 1（新規）
├── skills/
│   └── doc-review/
│       └── SKILL.md              # Layer 2（新規）

~/workspace-ai/nomuraya-aios/claude-os/
├── SPEC.md                       # このファイル
├── REVIEW-PLAN.md
├── packages/
│   ├── manifest.yaml             # doc-review エントリ追加
│   ├── skills/
│   │   └── doc-review/
│   │       └── SKILL.md          # Layer 2 の正本（新規）
│   └── agents/
│       ├── agent-doc-auditor.sh  # Layer 3（新規）
│       ├── deprecated-terms.txt  # 廃止パターン一覧（新規）
│       └── launchd/
│           └── ai.aios.agent-doc-auditor.plist  # Layer 3 launchd（新規）
└── patterns/
    └── v3-agent-roles.md         # agent-doc-auditor エントリ追加
```

### 依存関係
- `jq`（feedback.jsonl 投入）
- `gh`（/doc-review がIssue作成するケース、任意）
- `git`（agent-doc-auditor の git log 突合）
- `~/.claude/engineering-feedback/feedback.jsonl`（既存のフィードバックループ）

## 完了条件

- [ ] `~/.claude/rules/doc-llm-first.md` が存在し、4軸チェックリストが読める
- [ ] `~/.claude/rules/core-behaviors.md` 経由で `doc-llm-first.md` が CLAUDE.md に読み込まれる
- [ ] `/doc-review path/to/doc.md` を呼ぶと4軸スコアテーブルが出力される
- [ ] NG判定があると `feedback.jsonl` に `scope: "documentation"` エントリが追加される
- [ ] `agent-doc-auditor.sh --dry-run` を実行すると検出結果が標準出力に出る（実際の投入はしない）
- [ ] `manifest.yaml` に `doc-review` エントリが追加されている
- [ ] `v3-agent-roles.md` に `agent-doc-auditor` エントリが追加されている
- [ ] launchd plist が `~/Library/LaunchAgents/` に配置されローカルで登録可能な状態

## 実装時の注意点

- `agent-doc-auditor.sh` は oh-dispatch を使わない（テキスト生成不要、shell の grep/git のみ）
- feedback.jsonl のエントリに `scope: "documentation"` を必ず付ける（将来の振り分けのため）
- /doc-review スキルは LLM が評価するため、チェック観点が曖昧だと品質がブレる。4軸の NG 判定基準を具体的に書くこと
- deprecated-terms.txt は将来の拡張を想定して外部ファイル化する（スクリプトにハードコードしない）
- トークン爆発リスク: agent-doc-auditor は LLM 呼び出しなし。/doc-review は1ファイル1回の評価のみ（ループなし）
