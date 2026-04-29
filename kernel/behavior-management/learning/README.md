# Learning — 失敗から振る舞いを更新する

セッションで発覚した失敗パターンを次セッションに引き継ぎ、再発防止に組み込む3層構造。

## 3層構造

| 層 | 用途 | 寿命 |
|---|---|---|
| **memory** | プロジェクト固有 memory に失敗パターンを記録（自動ロード） | 中（プロジェクト終了まで） |
| **ADR** | 撤回時の Why と再発防止策を Architecture Decision Record として永続化 | 長（永続） |
| **future_concerns** | JSON `_meta` に長期課題として構造化 | 短〜中（案件単位） |

## フロー

```
失敗発生
  ↓
即「指摘が正しい」と認める（1行・反論禁止）
  ↓
撤回コスト定量化（修正ファイル数・コミット回数）
  ↓
ADR Why に経緯記録（<repo>/docs/adr/）
  ↓
memory に失敗パターン追加（~/.claude/projects/<repo>/memory/）
  ↓
Spec / Enforcement の更新で再発防止
  ↓
ベースライン値の見直し（measure_session_quality.py 再実行）
```

## ファイル配置（標準）

```
<repo>/docs/adr/000N-<topic>.md          # ADR永続化
<repo>/<data>.json _meta.future_concerns  # 構造化長期課題
~/.claude/projects/<repo>/memory/         # 自動ロード memory
  ├── MEMORY.md                            # インデックス
  └── feedback_<domain>_<date>.md          # 失敗パターン記録
```

## memory ファイルのテンプレート

```markdown
---
name: <DOMAIN>設計時の構造的失敗パターン（<YYYY-MM-DD>セッション学習）
description: <repo>内の<DOMAIN>タスク設計時に再発しやすい構造的失敗パターン
type: feedback
---

# <DOMAIN>設計時の構造的失敗パターン

## 経緯

<セッションで発生した撤回・指摘の概要>

## N個の構造的失敗パターン

### A. <パターン名>

**Why**: <なぜ起きるか>
**実例**: <セッションでの具体例>
**How to apply**: <次セッションでどう避けるか>

...
```

## ADR テンプレート（撤回経緯記録用）

```markdown
---
id: ADR-XXXX
title: <撤回の主題>
status: Accepted
date: YYYY-MM-DD
tags: [training-design, retraction, learning]
---

## Context

<何が起きたか>

## Decision

<採用した方針>

## Why（撤回理由 - 最重要）

<なぜ撤回したか・前提誤りの根本原因>

## 再発防止策（同セッション内で実装）

- Spec への反映: <ファイルパス>
- Enforcement の更新: <ファイルパス>
- Measurement の追加: <ファイルパス>
```

## 実証ケース

paiza/training-design:
- ADR: `paiza/docs/adr/0006-dev-exercise-design-philosophy.md`（11原則 + 撤回経緯）
- memory: `~/.claude/projects/-Users-nomuraya-workspace-ai-nomuraya-jobs-paiza/memory/feedback_training_design_failures_2026_04_29.md`（8パターン）
- future_concerns: `paiza/cases/2026-05-uluru/derived/intermediate/uluru_2026_05_data.json` `_meta.future_concerns`（VCS未利用案件対応・チーム間ファイル連携・受講生にサポート役を割り振った設計の再発防止）

主な学習:
- 「ken=テックリード/hi=サブテックリード」を構造化データまで実装してから撤回 → ADR-0006 原則11新設
- 自己申告1回 vs 客観測定11件（1100%乖離） → 自己評価信頼性低下を Spec §3.2.1 / §8 に明記
