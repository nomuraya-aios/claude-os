## 自動実行パイプラインでの LLM 呼び出し禁止

バックグラウンドスクリプト・launchd ジョブ・Stop/SessionStart hook チェーンで **いかなるLLMプロバイダーも呼んではならない**。

**対象（全て禁止）:**
- Anthropic API（claude -p）
- OpenRouter（oh-dispatch）
- Ollama API
- その他 LLM API

**なぜ OpenRouter も禁止か（2026-04-16 発見）:**
sync-update-system-prompt.sh が oh-dispatch を Stop hook チェーンから毎セッション呼び出し、
pattern-frequency.md (599KB) を渡していた。Anthropic API ではないが **トークン爆発リスクは同じ**。

**なぜ全自動パイプラインが対象か:**
- Stop hook → aggregate-patterns.sh → sync-update-system-prompt.sh のように、
  呼び出し元が LLM 不使用でもチェーン内の下流で LLM を呼ぶケースがある
- launchd の plist に `improve` を登録して oh-dispatch が走る（2026-04-16 即撤回）

**判定基準:**
```
Q: このスクリプトは人間の操作なしで実行されるか？
  YES → LLM呼び出し禁止
  NO（ユーザーが手動で実行）→ 許可
```

**代替手段:**
- セッション開始時の軽量チェック: top-patterns.md (1KB) を Read → AI が差分判定
- 月次フルレビュー: /persona-review でユーザーが明示指示
- 手動改善: `feedback-loop.sh improve` を対話的に実行

**例外（Claude CLI 必須）:**
| ジョブ | ファイル | 理由 |
|-------|---------|------|
| 日報生成 | `~/.claude/adk-agents/daily-report-agent/report_generator.py` | Sonnet品質が必須 |

例外追加条件: 無料プロバイダーで品質不足を実測確認＋このファイルに登録

**事故記録:**
- 2026-04-11: claude -p によるトークン爆発事故（Anthropic API 直接呼び出し）
- 2026-04-16: oh-dispatch 599KB 毎セッション呼び出し発見（sync-update-system-prompt.sh 廃止）
- 2026-04-16: launchd に oh-dispatch improve 登録→即撤回（feedback-loop.sh → collect のみに変更）
