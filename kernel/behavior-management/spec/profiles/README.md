# Domain Profiles — ドメイン別AI振る舞いプロファイル

各ドメインプロファイルは `../core.md`（共通コア仕様）を **前提として** ドメイン固有の追加仕様だけを記述する。

## プロファイル一覧

| プロファイル | 状態 | 実証 |
|---|---|---|
| [training-design.md](training-design.md) | 実装済 | ✅ paiza/uluru-2026-04-29 で実証（OS化の起点） |
| [coding.md](coding.md) | サンプル | ⚠️ 未実証（実装ガイド） |
| [writing.md](writing.md) | サンプル | ⚠️ 未実証（実装ガイド） |
| [ops.md](ops.md) | サンプル | ⚠️ 未実証（実装ガイド） |

## プロファイル作成手順

1. core.md を読んで共通仕様を理解
2. `template.md` を コピー（`cp ../template.md profiles/<domain>.md`）
3. ドメイン固有の判断軸・主語パターン・発話禁止リスト・思考エンジンを追加
4. 共通仕様と重複する記述は **削除**（core.md を参照する形に）
5. 実証実験フレーム（measurement / enforcement）を構築
6. ベースライン取得後、本 README に「実証済」マークを追加
