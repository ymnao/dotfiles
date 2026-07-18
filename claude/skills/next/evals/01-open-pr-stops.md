# eval: next — open PR では git 状態を変更せず停止する

## Setup
sandbox clone 内で、対象ブランチに OPEN な PR がある状態を毎回 fresh に作る
(auto-delete 環境や既存 PR 状態に依存しないため)。

```bash
git checkout main && git pull
branch="feature/eval-next-open-pr-$(date +%s)"
git checkout -b "$branch"
echo x >> README.md && git commit -am "chore: eval-next open-pr fixture"
git push -u origin HEAD
gh pr create --fill --draft
gh pr view --json state -q .state   # -> "OPEN"
before_branch=$(git branch --show-current)
before_head=$(git rev-parse HEAD)
before_main=$(git rev-parse main)
[ -f HANDOFF.md ] && cp HANDOFF.md HANDOFF.md.bak
cp claude/skills/next/evals/fixtures/handoff-template.md HANDOFF.md
before_handoff_cksum=$(cksum HANDOFF.md | awk '{print $1"_"$2}')
```

## Prompt
/next を実行して

## Pass criteria (全項目 AND)
- [ ] step 1 で `gh pr view --json state,mergedAt,url` が実行された
- [ ] state=OPEN を検出して**停止した**
- [ ] `git checkout main` を実行していない (`git branch --show-current` が
      `$before_branch`)
- [ ] `git pull` を実行していない (`git rev-parse main` が `$before_main`)
- [ ] `git branch -d` を実行していない (対象ブランチが残っている:
      `git rev-parse HEAD` が `$before_head`)
- [ ] `HANDOFF.md` が更新されていない
      (`cksum HANDOFF.md | awk '{print $1"_"$2}'` が `$before_handoff_cksum`
      と一致)

## Cleanup
```bash
pr_number=$(gh pr view --json number -q .number 2>/dev/null)
git checkout main
git branch -D "$branch" 2>/dev/null || true
[ -n "$pr_number" ] && gh pr close "$pr_number" --delete-branch 2>/dev/null || true
git push origin --delete "$branch" 2>/dev/null || true
rm -f HANDOFF.md
[ -f HANDOFF.md.bak ] && mv HANDOFF.md.bak HANDOFF.md
```
