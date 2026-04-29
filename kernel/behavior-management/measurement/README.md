# Measurement — 振る舞い品質の定量測定

AI振る舞い仕様が実際に機能しているかを **客観値** で測る。AIの自己評価は楽観的すぎる（実測との乖離10倍超の前例あり）。

## テンプレート

`measure-template.py` をコピーして使う。ドメイン固有のキーワード正規表現とメトリクスを編集。

```bash
cp claude-os/kernel/behavior-management/measurement/measure-template.py \
   <repo>/tools/src/measure_<domain>_quality.py
```

## 測定対象（汎用カテゴリ）

| カテゴリ | 指標例 |
|---|---|
| 思考プロセス遵守度 | 特定 tool_use パターンの回数 |
| 対話スタイル違反 | 発話禁止リストの出現頻度 |
| 失敗パターン再発 | キーワードベース検出（ドメイン固有） |
| ベースライン比較 | before/after delta |
| 期間正規化 | 1日あたり/1タスクあたりに換算 |

## 期間正規化（重要）

絶対値ではなく **1日あたり / 1タスクあたり** で評価する。

```bash
uv run python tools/src/measure_<domain>_quality.py \
  --jsonl <session.jsonl> \
  --git-since 2026-04-29 \
  --label "<case>-<date>" \
  --days 20 \
  --baseline cases/_baselines/<previous>.json
```

`--days` で期間を指定すると `<metric>_per_day` が算出される。これで他セッションと比較可能に。

## ベースライン管理

```
<repo>/cases/_baselines/
  ├── <case1>-<date>.json  # ベースライン
  └── <case2>-<date>.json  # 比較対象
```

## 実証ケース

paiza/training-design:
- スクリプト: `paiza/tools/src/measure_session_quality.py`
- ベースライン: `paiza/cases/_baselines/uluru-2026-04-29.json`
- 実測値:
  - LMSマッピング 159回 = 8回/日（20日間）
  - 確認系過多発 46回（強化版正規表現）
  - data_readiness_score 85/100
- 期待値: PSC案件で 1日あたり 5.5-6.5回（20-30%削減）
