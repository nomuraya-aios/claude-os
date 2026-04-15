---
name: doc-review
description: ドキュメント品質を4軸（判断可能・実装突合・更新トリガー・陳腐化検出）でチェック。問題は feedback.jsonl に投入。
---

# Doc-Review Skill - ドキュメント4軸チェック

## 目的

ドキュメントを LLMファースト な品質基準で検査し、問題を feedback.jsonl に記録する。
「書いた = 完了」ではなく「LLMが使える状態を継続的に保つ」ことをサポート。

---

## トリガー

**発動キーワード**: `ドキュメントレビュー`, `doc-review`, `ドキュメント確認`, `/doc-review`

**引数**:
- `/doc-review path/to/doc.md` — 特定ドキュメントをチェック
- `/doc-review` — カレントディレクトリの .md ファイルをスキャン

---

## 実行内容

### Step 1: ドキュメント取得

**引数あり**: 指定パスのドキュメントを Read

**引数なし**: カレントディレクトリの .md ファイルを列挙
```bash
find . -name "*.md" -type f -not -path "./.git/*" | head -20
```

複数ファイルがある場合は以下を実施:
- 最初の3ファイルを自動チェック（負荷分散）
- 残りは「`/doc-review {path}` で個別チェック可能」とユーザーに案内

### Step 2: 4軸チェック（LLM評価）

ドキュメントを以下の4軸で評価。各軸をスコア（OK/WARNING/NG）と理由で記録。

#### 軸1: 判断可能か
- **質問**: 「このドキュメントだけを読んだLLMが、ここに書いてある判断を実装できるか？」
- **NG判定例**:
  - 「詳細は別ファイル参照」で参照先が不明
  - 条件分岐の説明がない
  - 複数の選択肢があるのに「どれを使う？」の判断基準がない
- **OK判定例**: 判断に必要な情報が自己完結しており、参照先が具体的

#### 軸2: 実装と突合できるか
- **質問**: 「ドキュメント内のファイルパス・コマンド・スクリプト名が現在の実装と一致しているか？」
- **チェック方法**:
  ```bash
  # ドキュメント内に記載されたファイルパスが存在するか
  grep -E "^/|^\$|^~" {doc} | xargs -I {} ls -la {} 2>/dev/null || echo "MISSING"
  
  # コマンド・スクリプト名が実装に存在するか
  grep -r "script_name\|command_name" {codebase}
  ```
- **NG判定例**:
  - ファイルパスが存在しない
  - API キー名が現在の実装と異なる
  - 廃止済みスクリプト名を引用している
- **OK判定例**: 全パス・コマンド・設定値が確認可能

#### 軸3: 更新トリガーが定義されているか
- **質問**: 「『いつ見直すか』が明確に書いてあるか？」
- **NG判定例**:
  - 「最終更新: 2026-04-01」だけで見直しタイミングが不明
  - 「実装変更時」のみで、何が変更されたら対象か不明
- **OK判定例**:
  - 「〜ファイルが変更されたとき」
  - 「30日毎」「月1回」など周期が明記
  - 「API キーローテーション時」など具体的なイベント
- **WARNING判定例**: トリガーはあるが曖昧（「定期的に」など）

#### 軸4: 陳腐化サインが検出できるか
- **質問**: 「廃止済みスクリプト・古いフォールバック順・存在しないパスを機械的に見つけられるか？」
- **チェック方法**:
  ```bash
  # deprecated-terms.txt との突合
  grep -F -f {deprecated-terms.txt} {doc}
  ```
- **NG判定例**:
  - ドキュメント内に「廃止済み」と記されているのに grep で引っかからない形式
  - 複数パターン（`claude -p` vs `claude_p`）が混在
  - 廃止パターンが不完全（実装では廃止だが doc に載っている）
- **OK判定例**: コマンド・パス・スクリプト名が一貫した形式で、外部ファイル（deprecated-terms.txt）で廃止パターンを管理

### Step 3: 結果を表形式で出力

```markdown
## ドキュメント4軸チェック結果

**対象**: {ドキュメントパス}
**実施日時**: {JST日時}

| 軸 | 内容 | スコア | 理由 | 修正案 |
|----|------|--------|------|--------|
| 1 | 判断可能か | {OK/WARNING/NG} | {理由} | {修正案（NGの場合）} |
| 2 | 実装突合 | {OK/WARNING/NG} | {理由} | {修正案（NGの場合）} |
| 3 | 更新トリガー | {OK/WARNING/NG} | {理由} | {修正案（NGの場合）} |
| 4 | 陳腐化検出 | {OK/WARNING/NG} | {理由} | {修正案（NGの場合）} |
```

### Step 4: feedback.jsonl に投入（NG判定時のみ）

NG が1件以上ある場合、以下を `~/.claude/engineering-feedback/feedback.jsonl` に追加:

```bash
jq -n \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg doc_path "{ドキュメントパス}" \
  --arg scope "documentation" \
  --arg severity "ng" \
  --arg issue "{NG判定の軸と理由}" \
  --arg suggestion "{修正案}" \
  '{
    timestamp: $timestamp,
    doc_path: $doc_path,
    scope: $scope,
    severity: $severity,
    issue: $issue,
    suggestion: $suggestion,
    automated_by: "doc-review"
  }' >> ~/.claude/engineering-feedback/feedback.jsonl
```

### Step 5: WARNING / NG があれば修正案を提示

修正案の例:

```markdown
## 修正案

### 軸2: 実装突合 (NG)

**問題**: ドキュメント内の `/path/to/old-script.sh` が実装に存在しない

**修正**:
1. 現在のスクリプトパスを確認: `ls ~/workspace-ai/.../new-script.sh`
2. ドキュメント内の参照を更新
3. `/doc-review` で再確認
```

---

## 使用例

```bash
# 特定ドキュメントをチェック
/doc-review ~/.claude/rules/oh-dispatch-usage.md

# カレントディレクトリの .md をスキャン
/doc-review

# 問題が見つかった場合の次ステップ
# → feedback.jsonl に投入 + 修正案を提示
# → agent-system-improver.sh が週次で回収して改善パッチを提案
```

---

## 実装時の注意点

- **LLM評価のブレ防止**: 4軸の NG 判定基準を具体的に提示してから評価する
- **トークン爆発リスク**: 1ドキュメント1回の評価のみ。ループなし
- **feedback.jsonl との互換性**: `scope: "documentation"` を必ず付ける（振り分け用）
- **引数なし時の負荷**: 最初の3ファイルのみ自動チェック。残りはユーザー指示待ち

---

## 関連ファイル

| 用途 | パス |
|------|------|
| LLMファースト基準（SSOT） | `~/.claude/rules/doc-llm-first.md` |
| フィードバック投入先 | `~/.claude/engineering-feedback/feedback.jsonl` |
| 廃止パターン一覧 | `~/workspace-ai/nomuraya-aios/claude-os/packages/agents/deprecated-terms.txt` |
| 自動監査スクリプト | `~/workspace-ai/nomuraya-aios/claude-os/packages/agents/agent-doc-auditor.sh` |

---

## メンテナンス

**このスキル自体の更新トリガー**:
- 4軸チェック基準が変わったとき（doc-llm-first.md の更新に追従）
- feedback.jsonl の形式が変わったとき
