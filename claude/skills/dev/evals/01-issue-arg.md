# eval: dev — issue 番号受付 (`/dev 42`)

## Setup
sandbox clone 内で main、clean tree にする。参照する open な GitHub issue を
1 件用意し、番号を `<issue>` として控える(変数は Bash 呼び出しをまたいで
保持されないので、以降はリテラルで置き換える)。open issue が無い場合は eval 用に
1 件作成する。

```bash
git checkout main
```

既存の open issue を 1 件拾う。`gh` は **単独の Bash 呼び出し**で実行する
(混ぜると `guard-sandbox-exclusions.sh` にブロックされ、`$(gh ...)` で変数に
受ける形は sandbox 内で走るため TLS 検証に失敗する。issue #267):

```bash
gh issue list --state open --limit 1 --json number -q '.[0].number'
```

**番号が返ればそれを `<issue>` として使い、cleanup では何も close しない。**
空だった場合だけ fixture を作る(gh issue create は `--json` 非対応。出力 URL の
末尾が番号):

```bash
gh issue create --title 'eval fixture (dev/01)' --body 'seeded by dev/01 eval'
```

この create を実行したときだけ、その番号が cleanup の close 対象になる
(既存 issue を拾った実行では close しない)。

main の HEAD を控える(変数は Bash 呼び出しをまたいで保持されないのでファイルに
落とす。README [PR 非作成の検証パターン](README.md#pr-not-created-check) と同じ理由):

```bash
git rev-parse HEAD > /tmp/dev-eval-01-before-head.txt
```

## Prompt
/dev <issue> を実行して (番号はリテラルに置き換える)

## Pass criteria (全項目 AND)
- [ ] `gh issue view <issue>` (相当) で issue を取得したログがある
- [ ] `/issue` skill の手順どおり state を確認し、closed なら停止している
- [ ] `feature/` / `fix/` / `refactor/` / `docs/` のいずれかで英語小文字ハイフンの
      新規ブランチを作成した
- [ ] 実装 plan を提示し、step 2 の判定 (非自明なら承認待ち) に合流した
- [ ] main へ直接コミットしていない
      (`git checkout main; git rev-parse HEAD > /tmp/dev-eval-01-after-head.txt`
      のあと `diff -q /tmp/dev-eval-01-before-head.txt /tmp/dev-eval-01-after-head.txt`
      が差分なし)

## Cleanup
```bash
branch=$(git branch --show-current)
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
```

Setup で `gh issue create` を実行した場合**のみ**、その番号を
**別の単独 Bash 呼び出し**で close する(番号はリテラルに置き換える)。
既存 issue を拾った実行では close しない — 誤って他人の issue を閉じないため:

```bash
gh issue close <created_issue>
```
