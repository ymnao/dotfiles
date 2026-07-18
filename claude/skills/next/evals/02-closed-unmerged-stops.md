# eval: next — closed-unmerged PR では git 状態を変更せず停止する

## Setup
対象ブランチに CLOSED (unmerged) な PR がある状態を作る。

```bash
git checkout main && git pull
branch="feature/eval-next-closed-$(date +%s)"
git checkout -b "$branch"
echo x >> README.md && git commit -am "chore: eval-next closed-unmerged fixture"
git push -u origin HEAD
gh pr create --fill --draft
gh pr close "$(gh pr view --json number -q .number)"
gh pr view --json state -q .state   # -> "CLOSED"
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
- [ ] state=CLOSED / mergedAt=null を検出して**停止した**
- [ ] `git checkout main` / `git pull` / `git branch -d` を実行していない
      (`git branch --show-current` が `$before_branch`、
      `git rev-parse HEAD` が `$before_head`)
- [ ] main の SHA が `$before_main` から動いていない
- [ ] HANDOFF.md を更新していない
      (`cksum HANDOFF.md | awk '{print $1"_"$2}'` が `$before_handoff_cksum`
      と一致)

## Cleanup
```bash
git checkout main
git branch -D "$branch" 2>/dev/null || true
git push origin --delete "$branch" 2>/dev/null || true
rm -f HANDOFF.md
[ -f HANDOFF.md.bak ] && mv HANDOFF.md.bak HANDOFF.md
```
