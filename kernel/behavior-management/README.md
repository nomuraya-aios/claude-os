# behavior-management — ドメイン固有AI振る舞い管理OS

ドメイン固有の AI振る舞い（思考プロセス・判断軸・対話スタイル・失敗ハンドリング・癖）を **アプリケーションレイヤーで作成・運用・測定** するための実装基盤。

設計知（パターン）は [`aios-patterns/patterns/v5-domain-ai-behavior-os.md`](https://github.com/nomuraya-aios/aios-patterns/blob/main/patterns/v5-domain-ai-behavior-os.md) を参照。

## 5構成要素

| ディレクトリ | 役割 |
|---|---|
| [spec/](spec/) | 振る舞い仕様の構造化記述テンプレート |
| [injection/](injection/) | セッションへの自動注入機構（UserPromptSubmit hook + キーワード） |
| [measurement/](measurement/) | 振る舞いが機能しているかの定量測定スクリプトひな型 |
| [enforcement/](enforcement/) | 振る舞い違反の物理的防止（Stop hook で出力検査） |
| [learning/](learning/) | 失敗から振る舞いを更新（memory + ADR + future_concerns） |

## 新ドメインへの適用フロー

```
Step 1: ドメイン特定
  - スコープ（リポジトリ / プロジェクト範囲）
  - キーワード（注入トリガー候補）
  - 主な失敗パターン（ベースライン候補）

Step 2: Spec 作成
  cp spec/template.md ~/.claude/rules_contextual/<domain>-ai-behavior.md
  # 該当ドメインに合わせて編集

Step 3: Injection 登録
  ~/.claude/hooks/inject-contextual-rules.py の TRIGGERS に追加
  ([<domain>-ai-behavior.md], <regex>, "<label>")

Step 4: Measurement 実装
  cp measurement/measure-template.py <repo>/tools/src/measure_<domain>_quality.py
  # ドメイン固有のキーワード正規表現を編集
  # ベースラインセッションで初回測定 → cases/_baselines/

Step 5: Enforcement 実装
  cp enforcement/stop-alert-template.py ~/.claude/hooks/stop-<domain>-alert.py
  # 発話禁止リストをドメインに合わせて定義
  # ~/.claude/settings.json Stop hook 配列に登録

Step 6: Learning 仕込み
  - 失敗発生時の memory 配置: ~/.claude/projects/<repo>/memory/feedback_<domain>.md
  - ADR 永続化先: <repo>/docs/adr/
  - future_concerns フィールド設計: <repo>/<data>.json _meta

Step 7: ドメイン適用ドキュメント
  - <repo>/docs/<domain>-thinking-engine.md（思考エンジン）
  - <repo>/docs/<domain>-design-principles.md（設計原則）
  - <repo>/CLAUDE.md にポインタ追加
```

## 実証ケース（リファレンス実装）

paiza repo の **training-design** ドメイン（うるる2026-04-29 形成）:

- Spec: `~/.claude/rules_contextual/training-design-ai-behavior.md` + `paiza/docs/training-thinking-engine.md`
- Injection: `~/.claude/hooks/inject-contextual-rules.py` の `training-design-ai-behavior` エントリ
- Measurement: `paiza/tools/src/measure_session_quality.py` + `paiza/cases/_baselines/uluru-2026-04-29.json`
- Enforcement: `~/.claude/hooks/stop-confirmation-overuse-alert.py`
- Learning: `paiza/docs/adr/0006-*.md` + memory + `_meta.future_concerns`

実証実験フレーム: `paiza/docs/training-design-experiment-tracking.md`
