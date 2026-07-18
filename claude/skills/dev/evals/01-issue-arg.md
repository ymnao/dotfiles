# eval: dev — issue 番号受付 (`/dev 42`)

## Setup
sandbox clone 内で main、clean tree にする。参照する open な GitHub issue を
1 件用意し、番号を `$issue` に保存する。open issue が無い場合は eval 用に
1 件作成する。

```bash
git checkout main && git pull
issue=$(gh issue list --state open --limit 1 --json number -q '.[0].number')
created_issue=""
if [ -z "$issue" ]; then
    # gh issue create は --json 非対応、URL 末尾から番号を抽出する
    issue_url=$(gh issue create --title 'eval fixture (dev/01)' \
        --body 'seeded by dev/01 eval')
    issue=${issue_url##*/}
    created_issue="$issue"   # cleanup で eval が作った分だけ close する
fi
echo "issue: $issue"
before_head=$(git rev-parse HEAD)
```

## Prompt
/dev $issue を実行して

## Pass criteria (全項目 AND)
- [ ] `gh issue view $issue` (相当) で issue を取得したログがある
- [ ] `/issue` skill の手順どおり state を確認し、closed なら停止している
- [ ] `feature/` / `fix/` / `refactor/` / `docs/` のいずれかで英語小文字ハイフンの
      新規ブランチを作成した
- [ ] 実装 plan を提示し、step 2 の判定 (非自明なら承認待ち) に合流した
- [ ] main へ直接コミットしていない (`git checkout main && git rev-parse HEAD`
      が `$before_head` と同じ)

## Cleanup
```bash
branch=$(git branch --show-current)
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
[ -n "$created_issue" ] && gh issue close "$created_issue" 2>/dev/null || true
```
