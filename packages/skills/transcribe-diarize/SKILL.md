---
name: transcribe-diarize
description: 動画/音声の文字起こしと話者分離。
allowed-tools:
  - Bash
  - Write
  - Read
---

# 文字起こし＋話者分離スキル

## 目的

動画・音声ファイルから、話者ごとの発言録（語録ファイル）を自動生成する。

## 処理フロー

```
動画/音声ファイル
    ↓
ffmpegで音声抽出（wav変換）
    ↓
faster-whisper で文字起こし（large-v3, int8）
    ↓
pyannote で話者分離
    ↓
統合して語録ファイル出力
[SPEAKER_00] テキスト...
[SPEAKER_01] テキスト...
```

## 事前確認

```bash
# HuggingFaceログイン確認（pyannote利用に必要）
uv run --with huggingface_hub python3 -c "from huggingface_hub import whoami; print(whoami()['name'])"
```

ログインしていない場合: `huggingface-cli login`

## 実行手順

### Step 1: 音声抽出（mp4→wav）

```bash
INPUT="/path/to/input.mp4"
WAV="/tmp/meeting_audio.wav"

ffmpeg -i "$INPUT" -vn -acodec pcm_s16le -ar 16000 -ac 1 "$WAV" -y
```

### Step 2: 文字起こし＋話者分離スクリプト実行

```bash
OUTPUT="${INPUT%.*}_diarized.txt"

uv run --with pyannote.audio --with faster-whisper --with torch python3 - << 'EOF'
import os
from pyannote.audio import Pipeline
from faster_whisper import WhisperModel

audio_file = "/tmp/meeting_audio.wav"
output_path = "OUTPUT_PLACEHOLDER"

print("話者分離モデル読み込み中...")
pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1")

print("文字起こしモデル読み込み中...")
whisper = WhisperModel("large-v3", device="cpu", compute_type="int8")

print("話者分離中...")
diarization = pipeline(audio_file)

print("文字起こし中...")
segments, _ = whisper.transcribe(audio_file, language="ja", beam_size=5)
segments = list(segments)

print("統合して出力中...")
with open(output_path, "w", encoding="utf-8") as f:
    for segment in segments:
        speaker = "不明"
        for turn, _, spk in diarization.itertracks(yield_label=True):
            if turn.start <= segment.start <= turn.end:
                speaker = spk
                break
        line = f"[{speaker}] {segment.text.strip()}"
        print(line)
        f.write(line + "\n")

print(f"\n完了: {output_path}")
EOF
```

**注意**: `OUTPUT_PLACEHOLDER` を実際の出力パスに置き換える。

### Step 3: 出力確認

```bash
head -30 "$OUTPUT"
```

## 出力形式

```
[SPEAKER_00] こんにちは、今日はよろしくお願いします。
[SPEAKER_01] こちらこそよろしくお願いします。
[SPEAKER_00] では早速始めましょう。
```

話者名は `SPEAKER_00`, `SPEAKER_01` ... の形式。
必要に応じて後から置換で実名に変更可能:

```bash
sed -i '' 's/SPEAKER_00/山田/g; s/SPEAKER_01/鈴木/g' output.txt
```

## トラブルシューティング

### pyannoteが「File does not exist」エラー

mp4を直接渡すと失敗する場合がある。必ずffmpegでwav変換してから渡す。

### FP16 not supported on CPU警告

CPUのみの環境では正常な警告。`compute_type="int8"` を指定することで高速化。

### HuggingFaceトークンエラー

```bash
huggingface-cli login
# pyannote/speaker-diarization-3.1 の利用規約に同意が必要
# https://huggingface.co/pyannote/speaker-diarization-3.1
```

## 所要時間の目安（M2 Max / CPU）

| 音声長 | 文字起こし | 話者分離 | 合計 |
|--------|-----------|---------|------|
| 30分   | 10〜15分  | 5〜10分 | 15〜25分 |
| 60分   | 20〜30分  | 10〜15分 | 30〜45分 |
