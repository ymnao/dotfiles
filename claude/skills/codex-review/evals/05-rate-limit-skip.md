# eval: codex-review — rate limit 到達で ERROR ではなく SKIP (exit 4)

## Setup
実リミット到達は不要。mktemp で隔離した専用ディレクトリに偽 `codex`
実行ファイルを置いて usage limit 到達時の stderr 文言を再現する
(固定共有パスだと既存ファイルの上書き・cleanup での巻き込み削除があるため)。

```bash
mock_dir=$(mktemp -d "${TMPDIR:-/tmp}/codex-review-eval.XXXXXX")
cat > "$mock_dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "stream error: 429 Too Many Requests; you have hit your usage limit" >&2
exit 1
EOF
chmod +x "$mock_dir/codex"
```

## Prompt
レビュー対象リポジトリ (コミット済み差分のあるブランチ) の直下で、
04 と同じ前置き代入形式で PATH を渡して単体実行する:
```bash
PATH="$mock_dir:/usr/bin:/bin" bash "$HOME/.claude/skills/codex-review/scripts/run-review.sh" shell-senior
```
skill 全体を通した確認は任意: 同じ PATH 前置きが効いた shell で
`/codex-review を実行して` (最初の観点で偽 codex を踏む)。

## Pass criteria — 単体実行 (全項目 AND)
- [ ] exit 4 で終了する
- [ ] stdout に何も出ない (JSON も SKIP ログも出ない)
- [ ] stderr に偽 codex のメッセージと
      `[SKIP] codex-review <perspective>: codex account rate/usage limit reached` の両方が出る
- [ ] 裸の数値 429 だけを含む無関係 stderr (例: `connection to port 4290 failed`)
      では exit 4 にならない (exit 1 の ERROR になる) — 偽 codex の echo を
      差し替えて確認する

## Pass criteria — skill 全体 (任意実行時のみ)
- [ ] 当該 perspective が SKIPPED (rate limit) として報告表に記録され、
      「2 連続 ERROR で全体停止」のカウントに含まれない
- [ ] 残りの観点を実行せず skill 全体を即停止する (同一アカウントの
      同一リミット窓に当たるため)
- [ ] 呼び側 (pr / dev) への報告に第二意見フォールバック (Fable 系統
      サブエージェントのフレッシュレビュー) の案内が含まれる

## Cleanup
`rm -rf "$mock_dir"` (mktemp で作った専用ディレクトリのみ削除する)。
