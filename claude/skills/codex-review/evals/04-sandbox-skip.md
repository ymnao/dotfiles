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

レビュー対象リポジトリ (コミット済み差分のあるブランチ) の直下で `env` 経由で
PATH を渡して実行する (`export PATH=... &&` 形式は環境によっては書き込み
リダイレクトと同居させると弾かれるため、`env` 一発呼び出しにする):
```bash
env PATH="$TMPDIR/mock-bin:/usr/bin:/bin:/usr/local/bin" bash "$HOME/.claude/skills/codex-review/scripts/run-review.sh" shell-senior
```

## Prompt
単体確認: 上記コマンドを直接実行し exit code と stdout/stderr を見る。
skill 全体確認: `/codex-review を実行して` (このとき agent 自身の shell にも
同じ PATH 前置きが効いている sandbox 環境で走らせる、または 3 観点とも
同じ偽 codex が呼ばれるよう PATH を固定する)。

## Pass criteria (全項目 AND)
- [ ] `run-review.sh <perspective>` が exit 3 で終了する
- [ ] stdout に JSON (パース可能な review 結果) が出ない — 出るのは
      `[SKIP] codex-review <perspective>: sandbox blocks codex in-process app-server client init`
      という 1 行のログのみで、findings/verdict を含む JSON ではない
- [ ] stderr に偽 codex が出したメッセージ (`failed to initialize in-process app-server client`) が転記される
- [ ] /codex-review を通した場合: 当該 perspective が SKIPPED (sandbox) として
      報告表に記録され、「2 連続 ERROR で全体停止」のカウントに含まれず
      後続 perspective が続行される
- [ ] 3 観点すべて SKIP になった場合: 全体を停止し、Notes の
      「Running under a shell sandbox」に沿った unblock 手順 (sandbox 外実行
      または settings.json の permissions/network allowlist 拡張) を案内する

## Cleanup
```bash
rm -f "$TMPDIR/mock-bin/codex"
rmdir "$TMPDIR/mock-bin"
```
`rm -rf` は使わない (環境によって deny される)。個別 `rm` + `rmdir` で足りる。
削除を省略して `$TMPDIR` 配下に放置したままでも次回セットアップで
上書きされるため実害はない。
