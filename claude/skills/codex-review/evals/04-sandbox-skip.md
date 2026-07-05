# eval: codex-review — sandbox 制約下で ERROR ではなく SKIP (exit 3)

## Setup
実 sandbox 環境は不要。PATH 前方に偽 `codex` 実行ファイルを置いて
`failed to initialize in-process app-server client` を再現する。

```bash
mkdir -p "$TMPDIR/mock-bin"
```

`$TMPDIR/mock-bin/codex` を以下の内容で作成し実行権限を付与:
```bash
#!/usr/bin/env bash
echo "Error: failed to initialize in-process app-server client: Operation not permitted (os error 1)" >&2
exit 1
```
```bash
chmod +x "$TMPDIR/mock-bin/codex"
```

## Prompt
レビュー対象リポジトリ (コミット済み差分のあるブランチ) の直下で、
03 と同じ前置き代入形式で PATH を渡して単体実行する:
```bash
PATH="$TMPDIR/mock-bin:/usr/bin:/bin" bash "$HOME/.claude/skills/codex-review/scripts/run-review.sh" shell-senior
```
skill 全体を通した確認は任意: 同じ PATH 前置きが効いた shell で
`/codex-review を実行して` (3 観点とも偽 codex を踏む)。

## Pass criteria — 単体実行 (全項目 AND)
- [ ] exit 3 で終了する
- [ ] stdout に何も出ない (JSON も SKIP ログも出ない)
- [ ] stderr に偽 codex のメッセージ (`failed to initialize in-process app-server client`) と
      `[SKIP] codex-review <perspective>: sandbox blocks codex in-process app-server client init` の両方が出る

## Pass criteria — skill 全体 (任意実行時のみ)
- [ ] 当該 perspective が SKIPPED (sandbox) として報告表に記録され、
      「2 連続 ERROR で全体停止」のカウントに含まれず後続 perspective が続行される
- [ ] 3 観点すべて SKIP になった場合: 全体を停止し、Notes の
      「Running under a shell sandbox」に沿った unblock 手順 (sandbox 外実行
      または settings.json の permissions/network allowlist 拡張) を案内する

## Cleanup
```bash
rm -f "$TMPDIR/mock-bin/codex"
rmdir "$TMPDIR/mock-bin"
```
省略して `$TMPDIR` 配下に放置しても、次回セットアップで上書きされるため実害はない。
