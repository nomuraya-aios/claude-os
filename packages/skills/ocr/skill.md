# OCRスキル（NDLOCR-Lite）

<skill-info>
name: ocr
description: NDLOCR-LiteでOCR処理する（日本語印刷活字・PDF・画像対応）
trigger: OCR, 文字認識, 画像からテキスト, スキャンPDF
auto: false
user-invocable: true
</skill-info>

## 目的

画像・PDFファイルをNDLOCR-Liteで文字認識し、結果ファイルのパスを報告する。

---

## AI向け指示

<command-name>ocr</command-name>

### 引数パース

```
/ocr <パス>           # 単一ファイルまたはディレクトリ
/ocr <パス> --viz     # 認識領域の可視化画像も出力
```

引数がない場合はユーザーにパスを確認。

### 実行手順

#### 出力ディレクトリ決定

- 単一ファイル: 同じディレクトリに `ocr_out/` を作成
  - 例: `/path/to/image.jpg` → `/path/to/ocr_out/`
- ディレクトリ指定: そのディレクトリ内に `ocr_out/` を作成

```bash
# 単一ファイルの場合
OUTPUT_DIR="$(dirname '<パス>')/ocr_out"

# ディレクトリの場合
OUTPUT_DIR='<パス>/ocr_out'
```

#### ndlocr-lite 実行

```bash
# 単一ファイル
ndlocr-lite --sourceimg '<パス>' --output "$OUTPUT_DIR"

# ディレクトリ
ndlocr-lite --sourcedir '<パス>' --output "$OUTPUT_DIR"

# 可視化付き（--viz オプション時）
ndlocr-lite --sourceimg '<パス>' --output "$OUTPUT_DIR" --viz True
```

#### 結果確認と報告

```bash
ls -la "$OUTPUT_DIR"
```

出力ファイル（XMLが主）の内容を読んでユーザーに報告:
- 出力ディレクトリパス
- 生成ファイル一覧
- テキスト内容のサマリ（XMLからテキスト部分を抽出して表示）

XMLからテキスト抽出:
```bash
# XMLのテキスト内容だけ取り出す
grep -oP '(?<=<String CONTENT=")[^"]+' "$OUTPUT_DIR"/*.xml 2>/dev/null | head -50
# または
cat "$OUTPUT_DIR"/*.txt 2>/dev/null | head -100
```

### ndlocr-lite がない場合

```bash
command -v ndlocr-lite || echo "NOT_FOUND"
```

NOT_FOUND の場合:
```bash
uv tool install --python 3.13 "ndlocr-lite @ git+https://github.com/ndl-lab/ndlocr-lite.git"
```

### 初回実行時の注意

初回はONNXモデル（約160MB）が自動ダウンロードされる。時間がかかる旨をユーザーに伝える。

### 対応形式

- 画像: jpg / jpeg / png / tiff / tif / jp2 / bmp
- PDF: pypdfium2経由で自動変換

### 出力形式

- XML（メイン・構造化テキスト）
- JSON
- テキスト
- 可視化画像（`--viz True` 時）
