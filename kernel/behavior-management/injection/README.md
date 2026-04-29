# Injection — セッションへの自動注入機構

ドメイン固有の振る舞い仕様（`spec/template.md` で定義）を、ユーザープロンプトのキーワードに応じて **on-demand** で AI コンテキストに注入する。

## 実装

`~/.claude/hooks/inject-contextual-rules.py`（既存hook）の TRIGGERS 配列に新ドメインのエントリを追加する。

```python
TRIGGERS: list[tuple[list[str], re.Pattern[str], str]] = [
    # ... 既存エントリ
    (
        ["<domain>-ai-behavior.md"],
        re.compile(
            r"(<keyword1>|<keyword2>|<keyword3>)",
            re.IGNORECASE,
        ),
        "<domain>-behavior",
    ),
]
```

## キーワード設計指針

- **広すぎない**: 一般的すぎる単語は別ドメインで誤発火する
- **狭すぎない**: ユーザーが使う表現バリエーション（例: 「カリキュラム」「研修」「受講生」）を網羅
- **ドメイン固有名詞**: 案件名・プロジェクト名・専用ツール名を含める
- **動作トリガー**: 「設計する」「策定」「整備」など動詞も含める

## 動作確認

```bash
echo '{"prompt":"<テストキーワード>を含むプロンプト"}' | uv run python ~/.claude/hooks/inject-contextual-rules.py
```

→ 該当ドメインの spec が `<!-- Injected: contextual/<domain>-ai-behavior.md -->` として出力されれば成功。

## 設計判断（Why）

- 常時ロードすると トークンコスト爆発 → on-demand 注入
- @include 経由の固定ロードは判断分岐できない
- ユーザープロンプトが情報源なので、AIが介在せず判定できる

## 実証ケース

paiza/training-design ドメイン:
```python
(
    ["training-design-ai-behavior.md"],
    re.compile(
        r"(カリキュラム|研修案件|教育研修|受講生|学習者|paiza\s*LMS|"
        r"うるる|PSC|マルゴ|ヴィッツ|"
        r"開発演習|dev[- ]exercise|training[- ]design|"
        r"theme_per_date|day_outcomes|support_role_rules|curriculum_connections|"
        r"インプット.*講座|必須問題|追加問題|配列メニュー|"
        r"apply_curriculum|curriculum_edit\.py|"
        r"主語チェック|観測可能ゴール|3層思想|concept[- ]driven)",
        re.IGNORECASE,
    ),
    "training-design-ai-behavior",
),
```
