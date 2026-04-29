# Enforcement — 振る舞い違反の物理的防止

ドキュメント注入だけでは防げない違反を **Stop hook で出力検査 + 警告注入** することで物理的に検出する。

## 実装手順

1. テンプレート `stop-alert-template.py` を複製
   ```bash
   cp claude-os/kernel/behavior-management/enforcement/stop-alert-template.py \
      ~/.claude/hooks/stop-<domain>-alert.py
   chmod +x ~/.claude/hooks/stop-<domain>-alert.py
   ```

2. 発話禁止リスト（CONFIRMATION_PATTERNS）をドメインに合わせて編集

3. スコープ制限（PROJECT_REPO_PATH）を該当 repo に設定

4. settings.json の Stop hook 配列に登録
   ```json
   {
     "type": "command",
     "command": "~/.claude/scripts/hook-wrapper.sh ~/.claude/hooks/stop-<domain>-alert.py",
     "timeout": 5
   }
   ```

5. 動作確認
   ```bash
   echo '{"assistant_message":"<禁止パターンを含む応答>"}' | \
     uv run python ~/.claude/hooks/stop-<domain>-alert.py
   ```

## 安全装置（テンプレに既に組み込み済）

- **スコープ制限**: cwd が指定 repo 配下でなければスキップ（全プロジェクトで誤発動防止）
- **自己排除**: 警告メッセージ自身の引用は除外（誤検知防止）
- **stop_hook_active 時スキップ**: 無限ループ防止
- **timeout 5秒**: 重い処理になりにくい

## Why（ドキュメント注入だけでは不十分な理由）

うるるセッションでの実証:
- AI振る舞い仕様 §3.2.1 を **Markdown で** 書いた
- 同セッション内で同パターンが **5件発生** → 仕様を読んでも守れない
- 自己評価は「1回」と申告 → 客観測定で **11件検出**（1100%乖離）

→ ドキュメント注入は前提条件。実際の防止は hook で物理的に行う。

## 実証ケース

paiza/training-design:
- 実装: `~/.claude/hooks/stop-confirmation-overuse-alert.py`
- 検出パターン: 「実装するか?」「進めるか?」「推奨は即実装」「どうする?」「やるか?」等12パターン
- スコープ: paiza repo 配下のみ
- 動作: 検出時に additionalContext で次ターンに警告注入
