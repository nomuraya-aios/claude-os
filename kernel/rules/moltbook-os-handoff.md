---
name: moltbook AI-OS統合 handoff
type: kernel
protected: true
created: 2026-04-19
---

# moltbook AI-OS統合 — 次セッションへの引き継ぎ

## 背景（必ず読むこと）

moltbookは「人間が介入しなくても自己修復で回るシステム」を目的として作られた。
しかし現状は「動くが動き続けない」状態にある。

### なぜ動き続けないのか（git logから特定した根本原因）

1. **外部バイナリの仕様が文書化されていない**
   moltbook CLIの出力形式（JSONネスト構造、stdout/stderrの混在、エラー文字列）が
   実行してみるまでわからない。fix→fix→fixの連鎖はここから発生する。

2. **目的がセッションをまたいで消える**
   AIが「現状の実装に合わせてドキュメントを更新」する動きをする。
   2026-04-17に「自己修復」という目的がdocs/legacy/に移動されて現行ドキュメントから消えた。

3. **テストが実態と乖離しても検出されない**
   テストは存在するが、実装変更時にテストが更新されない。
   scripts/post.shがarchive/に移動されてもtest_post.pyが放置された。

### 本セッションで実施したこと

**claude-osをOSとして使い、moltbook用の「1台のPC」を構築し始めた。**

1. `kernel/rules/moltbook-purpose.md` — 目的をカーネルに固定（AIが消せない）
2. `kernel/hooks/pre-bash-kernel-protect.sh` — kernel/への変更をブロック
3. `~/.claude/hooks/pre-bash-kernel-protect.sh` — フックをClaude Codeに登録済み
4. `svc/discord-bot/bot.py` — Discord Ops Bot（launchd稼働中、PID 30173）
5. `svc/notify/enqueue.py`, `enqueue.sh`, `worker.py` — 通知キューの試作（未完成・未稼働）

---

## 次セッションでやること

### タスク1: moltbook svcをclaude-os registryに登録する

**Why:** registryに登録することで「プロセスが動き続けているか」をOSが監視できる。
現状はlaunchdが死活監視しているが、「動いているが正常に動いていない」を検出できない。

**具体的な作業:**

```bash
# claude-os registryの現状確認
ls ~/workspace-ai/nomuraya-aios/claude-os/registry/

# moltbook用のプロセス定義を作る
# 対象: safe-post, heartbeat, discord-bot の3プロセス
```

各プロセスが起動時にregistryに自分を登録し、終了時にunregisterする。
registryが定期的に生存確認して、死んでいたら自己修復を試みる。

**Done条件:**
- `registry-list.sh`でmoltbookの3プロセスが見える
- いずれかのプロセスが死んだ時、registryが検出してlaunchdを通じて再起動する
- 再起動に失敗した場合のみDiscord通知が飛ぶ

### タスク2: svc/notify/を完成させる

**Why:** 現状のnotify.shは「動くが通知が届かない」状態。
原因はDiscord Bot未招待（サーバーに参加していない）。

**現状:**
- `svc/discord-bot/bot.py` — launchd稼働中（PID 30173）だがBotがサーバーに未参加
- `svc/notify/worker.py` — 試作済みだが未稼働・設計が途中
- `svc/notify/enqueue.py`, `enqueue.sh` — 呼び出し元用インターフェース試作済み

**先にやること:**
1. BotをDiscordサーバーに招待する（Developer Portal → OAuth2 → URL Generator）
2. 招待後にチャンネルIDを再設定
3. worker.pyを起動してテストイベントを送信して動作確認

**notifyの設計原則（本セッションで合意した内容）:**

```
マスタ（worker.py）: 送信ロジック・エスカレーション判定・プロファイル白リスト
トランザクション（~/.moltbook/notify-queue/*.json）: イベント1件のデータのみ
  {event, message, detail, caller, caller_pid, enqueued_at}

呼び出し元: enqueue.py/enqueue.sh で1行書くだけ
worker: キューをポーリングしてマスタロジックで処理
```

**重要な設計上の議論（次セッションで継続）:**
- 冪等性はマスタ側で担保（トランザクションは「何を送るか」だけ持つ）
- エスカレーション状態の置き場所が未決定
- 「動くが動き続けない」を防ぐためにGoで書き直す案も出たが未決定

### タスク3: moltbook-purpose.mdをPOSTING.mdから参照させる

**Why:** kernel/の目的が実装ドキュメントから見えない状態だと、
次のAIが「kernelに目的がある」ことを知らずに実装を書く。

```bash
# POSTING.mdの先頭に以下を追加する
# ## 目的
# kernel/rules/moltbook-purpose.md を参照。
# このドキュメントはその目的を達成するための実装設計を記述する。
```

---

## 次セッションへのプロンプト

以下をそのままコピーして新セッションに貼る：

---

```
moltbookの運用改善を継続する。

背景を読んでから作業に入ること:
~/workspace-ai/nomuraya-aios/claude-os/kernel/rules/moltbook-os-handoff.md

現在の状況:
- claude-osをOSとして使い、moltbook用の「1台のPC」を構築中
- kernel/rules/moltbook-purpose.md に目的が固定済み（変更禁止）
- kernel/hooks/pre-bash-kernel-protect.sh がkernel保護フックとして稼働中

別セッションがlaunchd/投稿系の整備を行っている可能性がある。
作業開始前に git pull して最新状態を確認すること。

handoff記載のタスク1（registry登録）から着手する。
ただしhandoff-why-checkルールに従い、KGI/KPI/Done条件を確認してから実装に入ること。
```

---

## 現在稼働中のlaunchdジョブ（触らないこと）

| ジョブ | PID | 状態 |
|--------|-----|------|
| com.nora-oc.moltbook-discord-bot | 30173 | 稼働中 |
| com.nora-oc.moltbook-dashboard-server | 28959 | 稼働中 |
| com.nora-oc.moltbook-notify-worker | 未登録 | 未稼働 |

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `kernel/rules/moltbook-purpose.md` | 目的（変更禁止） |
| `svc/discord-bot/bot.py` | Discord Ops Bot本体 |
| `svc/notify/enqueue.py` | Python用キュー書き込み |
| `svc/notify/enqueue.sh` | Shell用キュー書き込み |
| `svc/notify/worker.py` | 通知ワーカー（未完成） |
| `~/.config/moltbook-discord-bot/config.json` | Bot token・channel設定 |
| `~/workspace-ai/nomuraya-aios/claude-os/registry/` | プロセスレジストリ |
