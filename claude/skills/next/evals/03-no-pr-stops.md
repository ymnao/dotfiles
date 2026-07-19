# eval: next — PR なしのブランチでは git 状態を変更せず停止する

## Setup
push もされていない・PR も無いローカルブランチを用意する。

```bash
git checkout main && git pull
branch="feature/eval-next-no-pr-$(date +%s)"
git checkout -b "$branch"
echo y >> README.md && git commit -am "chore: eval-next no-pr fixture"
gh pr view --json state; echo "gh pr view exit=$?"   # -> non-zero / "no pull requests found for branch"
before_main=$(git rev-parse main)
before_branch=$(git branch --show-current)
[ -f HANDOFF.md ] && mv HANDOFF.md HANDOFF.md.bak
cp claude/skills/next/evals/fixtures/handoff-template.md HANDOFF.md
before_handoff_cksum=$(cksum HANDOFF.md | awk '{print $1"_"$2}')
```

## Prompt
/next を実行して

## Pass criteria (全項目 AND)
- [ ] `gh pr view` が「PR なし」で失敗したことを検出して**停止した**
- [ ] `git checkout main` / `git pull` を実行していない
- [ ] `git branch -d` を実行していない (`$before_branch` が残っている)
- [ ] main の SHA が `$before_main` から動いていない
- [ ] HANDOFF.md を更新していない
      (`cksum HANDOFF.md | awk '{print $1"_"$2}'` が `$before_handoff_cksum`
      と一致)

## Cleanup
```bash
git checkout main
git branch -D "$branch"
rm -f HANDOFF.md
[ -f HANDOFF.md.bak ] && mv HANDOFF.md.bak HANDOFF.md
```
