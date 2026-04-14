---
name: tts
description: テキストをVOICEVOX/Irodori-TTSで音声変換・再生。
user-invocable: true
allowed-tools:
  - Bash
---

以下のコマンドを実行する。引数はユーザー入力から解釈する。

```bash
bash ~/.claude/scripts/tts.sh "テキスト" [--engine irodori] [--voice ID]
```

**引数の解釈**:
- デフォルト: VOICEVOX + ずんだもん (`--voice 3`)
- `--engine irodori`: Irodori-TTS (声質クローン) を使用
- `--voice ID`: VOICEVOX の話者 ID 、または Irodori-TTS の voice_id (WAV ファイル名)

ボイス一覧が必要なら: `curl -s http://localhost:8201/voices` (VOICEVOX) / `curl -s http://localhost:8200/voices` (Irodori-TTS)
