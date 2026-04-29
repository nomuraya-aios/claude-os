# training-design プロファイル

研修案件のカリキュラム設計・開発演習設計を行う AI 振る舞いプロファイル。

**前提**: `../core.md`（共通コア仕様）を必ず読む。本プロファイルはコアの拡張点のみ記述。

## 実装ファイル（実証済）

- 実体: `~/.claude/rules_contextual/training-design-ai-behavior.md`
- 注入: `~/.claude/hooks/inject-contextual-rules.py` の `training-design-ai-behavior` トリガー
- Stop hook: `~/.claude/hooks/stop-confirmation-overuse-alert.py`
- 測定: `paiza/tools/src/measure_session_quality.py`
- ベースライン: `paiza/cases/_baselines/uluru-2026-04-29.json`

形成セッション: 2026-04-29 paiza repo うるる2026-05案件

## ドメイン固有の主語パターン（core.md §4 拡張）

| 主語 | 判定 |
|---|---|
| 講師 | OK |
| 受講生（特定個人） | NG（責務転嫁） |
| チーム評価設計 | OK |
| 案件先担当者 | OK（事前確認等） |

## ドメイン固有の発話禁止リスト（core.md §1.1 追加）

共通リストに加えて:
- 「上位者は下位者をフォロー」
- 「Aさん=Bさん担当」のような個別ペアリング指示

## ドメイン固有の思考エンジン（5問モデル）

詳細: `paiza/docs/training-thinking-engine.md`

- Q1 受講生をどう捉えるか（4軸モデル: rating + バックグラウンド + 事前paiza活動 + 実務経験）
- Q2 1日をどう編むか（concept-driven + 3層思想 + 容量計算）
- Q3 詰まり対処（4段階フォールバック・時間軸マトリクス）
- Q4 シート↔JSON 同期（apply_per_date 聖域化）
- Q5 撤回時のチェック（主語・章番号・観測可能ゴール・既存原則矛盾）

## ドメイン固有のメトリクス

主要指標（時間消費の本丸）:
- LMSマッピング関連アクション/日（ベースライン: 8回/日 → 期待値 5.5-6.5回/日）
- マッピング判断の修正コミット数（ベースライン: 3 → 期待値 ≤1）

倫理 Kill Criteria:
- 受講生サポート役強要 = 0回（再発1回で即停止判断）

## 関連

- 実証実験フレーム: `paiza/docs/training-design-experiment-tracking.md`
- 着手時 Skill: `~/.claude/skills/training-design-start/`
- ADR: `paiza/docs/adr/0006-dev-exercise-design-philosophy.md`
- 設計原則: `paiza/docs/training-design-principles.md`
