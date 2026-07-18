# eval: dev — issue 番号受付 (`/dev 42`)

## Setup
sandbox clone 内で main、clean tree にする。参照する open な GitHub issue を
1 件用意する (以下 `<N>` とする)。

```bash
git checkout main && git pull
N=$(gh issue list --state open --limit 1 --json number -q '.[0].number')
echo "issue: $N"
```

## Prompt
/dev <N> を実行して

## Pass criteria (全項目 AND)
- [ ] `gh issue view <N>` (相当) で issue を取得したログがある
- [ ] `/issue` skill の手順どおり state を確認し、closed なら停止している
- [ ] `feature/` / `fix/` / `refactor/` / `docs/` のいずれかで英語小文字ハイフンの
      新規ブランチを作成した
- [ ] 実装 plan を提示し、step 2 の判定 (非自明なら承認待ち) に合流した
- [ ] main へ直接コミットしていない

## Cleanup
```bash
git checkout main
git branch -D <作成したブランチ>
```
