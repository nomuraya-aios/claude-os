# Issueドリブンプロセス ライフサイクル設計

**ステータス**: 設計中  
**関連Issue**: #8

---

## 設計思想

IssueをOSのプロセスとして扱う。UNIXプロセスモデルに倣い、
spawn→exec→running→exit→reapの全ステージを明示的に管理する。

**最重要原則**: プロセスは必ず終了する。終了しないプロセスは作らない。

---

## 適用範囲（重要）

このライフサイクル設計は**Issueベースのタスクプロセス**に適用する。
常駐プロセス（moltbook svc等）には適用しない。

| プロセス種別 | 設計 | 失敗時の挙動 |
|------------|------|------------|
| Issueタスク（doc-review等） | このドキュメント | `status:failed` → 人間確認 |
| 常駐svc（safe-post等） | `kernel/rules/moltbook-purpose.md` | 自己修復 → 回復不能なら通知 |

常駐プロセスに「失敗したら人間が確認」を適用すると
`kernel/rules/moltbook-purpose.md`の目的（人間介入なしに自己修復で回る）と矛盾する。

---

## ライフサイクル

```
Issue作成
    ↓
[spawn]   status:queued    キューに積まれた状態
    ↓
[exec]    status:running   ハンドラ起動・処理開始
    ↓
[exit]    終了コード確定   正常/失敗/スキップ/タイムアウト
    ↓
[reap]    status:done      Issueクローズ + 結果コメント + ログ記録
          status:failed    失敗ラベル + エラーコメント（再試行しない）
```

---

## ステータスラベル

| ラベル | 意味 | 遷移元 | 遷移先 |
|--------|------|--------|--------|
| `status:queued` | キュー待ち | Issue作成 | `status:running` |
| `status:running` | 処理中 | queued | `status:done` / `status:failed` / `status:timeout` |
| `status:done` | 正常完了 | running | Issueクローズ |
| `status:failed` | 異常終了 | running | 人間が確認・手動再実行（Issueタスク専用） |
| `status:timeout` | タイムアウト強制終了 | running | 人間が確認（Issueタスク専用） |

---

## 終了コード仕様

moltbookのissue-queue-runnerの設計を継承・拡張する。

| 終了コード | 意味 | 遷移 |
|-----------|------|------|
| 0 | 正常完了 | → done / Issueクローズ |
| 10 | ドライラン完了 | → done（Issueはオープンのまま） |
| 20 | スキップ（対象外と判定） | → done / Issueクローズ |
| 2 | 品質不合格 | → failed（再試行なし） |
| 124 | タイムアウト | → timeout |
| その他 | 異常終了 | → failed |

**再試行は行わない**。moltbookのretryポリシーはclaude-osでは採用しない。
理由: 失敗の原因を人間が確認せずに再試行するとトークン爆発するリスクがある。

---

## タイムアウト設計

```
MAX_TURNS=20          oh-dispatchのターン上限（ハンドラ内で必ず設定）
PROCESS_TIMEOUT=600   プロセス全体の最大実行時間（秒）= 10分
```

- `oh-dispatch --max-turns 20` を全ハンドラで必須とする
- `timeout 600 bash handler.sh` でプロセス全体を包む
- タイムアウト時は終了コード124 → `status:timeout`

---

## プロセステーブル

実行中プロセスを `state/process-table.jsonl` で管理する。

```jsonl
{"id": "uuid", "repo": "owner/repo", "issue": 1, "pid": 12345, "started_at": "...", "status": "running", "max_timeout": 600}
```

- spawn時にエントリ追加
- exit時にステータス更新
- launchd起動時に `status:running` のまま残っているエントリを検出 → timeout扱いで強制reap

---

## 冪等性保証

- `state/processed.txt` に `owner/repo:NUMBER` を記録（moltbook踏襲）
- running中の同一Issueへの二重起動を `process-table.jsonl` で防ぐ
- flockによるキューファイルの排他制御

---

## 正常終了フロー（reap）

```bash
# Issueに結果コメント
gh issue comment $ISSUE --repo $REPO --body "✅ 完了\n\n${RESULT_SUMMARY}"

# Issueクローズ
gh issue close $ISSUE --repo $REPO

# ステータスラベル更新
gh issue edit $ISSUE --repo $REPO \
  --remove-label "status:running" \
  --add-label "status:done"

# プロセステーブル更新
# ログ記録（logging/に書き込み）
```

---

## 異常終了フロー（reap on failure）

```bash
# Issueにエラーコメント（再試行しない旨を明記）
gh issue comment $ISSUE --repo $REPO \
  --body "❌ 失敗 (exit: $EXIT_CODE)\n\n${ERROR_LOG}\n\n⚠️ 自動再試行はしません。内容を確認してから手動で再実行してください。"

# Issueはオープンのまま残す（人間が確認できるように）
gh issue edit $ISSUE --repo $REPO \
  --remove-label "status:running" \
  --add-label "status:failed"

# プロセステーブル更新
# ログ記録
```

---

## ハンドラの実装規約

claude-os向けハンドラスクリプトが守るべきルール。

```bash
#!/bin/bash
# handler-xxx.sh
# 必須: タイムアウト・ターン上限・終了コード

set -euo pipefail

# 必須: oh-dispatchには必ずmax-turnsを指定
oh-dispatch -p "..." \
  --permission-mode full_auto \
  --max-turns 20

# 必須: 終了コードを明示
# 0=成功 / 2=品質不合格 / 20=スキップ / その他=失敗
exit 0
```

---

## watch-repos.yamlへの登録タイミング

**claude-osをissue-watcherに登録するのは以下が揃ってから**:

- [ ] このライフサイクル設計の実装完了（process-runner.sh）
- [ ] 各ハンドラにmax-turns・タイムアウトが設定されている
- [ ] security/audit.shでセキュリティチェックが通っている
- [ ] health/health-check.shが正常を返している

---

## moltbookとの差分

| 項目 | moltbook | claude-os |
|------|---------|-----------|
| 再試行 | あり（max_retries=3） | なし（人間確認必須） |
| タイムアウト | なし | 600秒強制終了 |
| max-turns | ハンドラ依存 | 20ターン必須 |
| 失敗時Issue | オープンのまま | オープン + failedラベル |
| キュー | issue-queue.jsonl | process-table.jsonl |
