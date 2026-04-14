# PDF読み込みスキル

<skill-info>
name: pdf
description: PDFファイルを安全に読み込む（AI内部用）
trigger: PDF読み込み, PDFを読みたい, このPDF, PDF開いて
auto: false
user-invocable: false
</skill-info>

## 目的

ユーザーが「このPDF読んで」と言ったとき、AIがこのスキルを参照して処理する。
ReadツールでのPDF読み込みはフックでブロックされているため、pdftotext等を使う。

---

## AI向け指示

<command-name>pdf</command-name>

### 実行手順

#### 1. ファイルパス取得

引数がない場合はユーザーに確認。

#### 2. ファイル存在確認

```bash
ls -la "<ファイルパス>"
```

#### 3. 通常のテキスト抽出（デフォルト）

**方法1: pdftotext（推奨）**
```bash
pdftotext -enc UTF-8 "<ファイルパス>" - 2>/dev/null
```
- `-` は標準出力への出力を意味
- インストール: `brew install poppler`

**方法2: Python pypdf**
```bash
uv run --python 3.11 python -c "
from pypdf import PdfReader
reader = PdfReader('<ファイルパス>')
for page in reader.pages:
    print(page.extract_text())
" 2>/dev/null
```
- インストール: `uv pip install pypdf`

**方法3: macOS組み込み（mdimport）**
```bash
mdimport -d2 "<ファイルパス>" 2>&1 | grep -A 1000 "kMDItemTextContent"
```
- 精度は低いがインストール不要

#### 4. テキストが抽出できない場合 → OCR

pdftotextで空またはほぼ空の場合、画像PDFの可能性。OCRを試す:

```bash
# tesseract で直接OCR（日本語対応）
# まずPDFを画像に変換してOCR
pdftoppm "<ファイルパス>" /tmp/pdf_page -png
for img in /tmp/pdf_page*.png; do
  tesseract "$img" - -l jpn+eng 2>/dev/null
done
rm -f /tmp/pdf_page*.png
```

**代替: ocrmypdf でOCRレイヤー追加**
```bash
# OCR付きPDFを生成してからテキスト抽出
ocrmypdf -l jpn+eng --skip-text "<ファイルパス>" /tmp/ocr_output.pdf 2>/dev/null
pdftotext -enc UTF-8 /tmp/ocr_output.pdf - 2>/dev/null
rm -f /tmp/ocr_output.pdf
```

**インストール**:
```bash
brew install tesseract tesseract-lang  # OCRエンジン + 言語パック
brew install ocrmypdf                   # PDF OCR wrapper
```

#### 5. 結果を報告

- テキスト化に成功したらユーザーに内容を報告
- 失敗した場合はツールのインストールを提案
- ユーザーが「保存して」と言ったらファイルに保存

**保存する場合**:
```bash
OUTPUT_PATH="${<ファイルパス>%.pdf}.txt"
pdftotext -enc UTF-8 "<ファイルパス>" "$OUTPUT_PATH"
echo "保存先: $OUTPUT_PATH"
```

### 禁止事項

- ❌ **Readツールで直接PDFを開かない**（フックでブロックされる）
- ❌ PDFのバイナリ内容を表示しない

### ツールがない場合の提案

```markdown
PDFをテキスト化するツールがインストールされていません。

**推奨**: poppler をインストール
\`\`\`bash
brew install poppler
\`\`\`

または Python の pypdf:
\`\`\`bash
uv pip install pypdf
\`\`\`
```

---

## トラブルシューティング

### 「Read tool blocked」と表示される

フックが正常に動作しています。このスキルで提供される方法を使ってください。

### 日本語が文字化けする

```bash
pdftotext -enc UTF-8 "<ファイルパス>" -
```

### ページ数が多すぎる

```bash
# 最初の5ページのみ
pdftotext -f 1 -l 5 "<ファイルパス>" -
```

### テキストが抽出されない（画像PDF）

スキャンPDFや画像埋め込みPDFの場合、`--ocr` オプションを使用:

```bash
/pdf ~/Downloads/scan.pdf --ocr
```

### OCRで日本語が認識されない

tesseractの日本語言語パックを確認:

```bash
tesseract --list-langs | grep jpn
# jpn がなければインストール
brew install tesseract-lang
```

### OCRが遅い

大きなPDFの場合、ページ範囲を指定:

```bash
# pdftoppmでページ指定
pdftoppm -f 1 -l 5 "<ファイルパス>" /tmp/pdf_page -png
```

---

## 更新履歴

- 2026-01-30: --save, --ocr オプション追加（テキスト保存、画像PDF対応）
- 2026-01-30: 初版作成（セッションクラッシュ再発防止）
