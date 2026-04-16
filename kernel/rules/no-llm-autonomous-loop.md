## LLM自律実行ループの禁止

以下のパターンを持つスクリプトは作ってはならない（2026-04-14 トークン爆発事故）。

| 禁止パターン | 具体例 |
|-------------|--------|
| ループ内でLLM繰り返し呼び出し | `for file in files; do claude -p ...; done` |
| 再処理フラグ | `--reprocess`, `--retry-all`, `--force-rerun` |
| LLM判定→続行の自律ループ | judge → score → 次 → judge → ... |
| commit後に次の処理を続ける無限改善 | commit → 「残りN件」→ commit → ... |

**代替:** 蓄積と実行を分離。LLM呼び出しは1スクリプト1回まで。
