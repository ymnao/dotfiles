# eval: next — closed-unmerged PR では git 状態を変更せず停止する

## Setup
対象ブランチに CLOSED (unmerged) な PR がある状態を作る。

```bash
git checkout main && git pull
git checkout -b feature/eval-next-closed-$(date +%s)
echo x >> README.md && git commit -am "chore: eval-next closed-unmerged fixture"
git push -u origin HEAD
gh pr create --fill --draft
gh pr close $(gh pr view --json number -q .number)
gh pr view --json state -q .state   # -> "CLOSED"
BEFORE_MAIN=$(git rev-parse main)
```

## Prompt
/next を実行して

## Pass criteria (全項目 AND)
- [ ] state=CLOSED / mergedAt=null を検出して**停止した**
- [ ] `git checkout main` / `git pull` / `git branch -d` を実行していない
- [ ] main の SHA が `BEFORE_MAIN` から動いていない
- [ ] HANDOFF.md を更新していない

## Cleanup
```bash
git checkout main
git branch -D feature/eval-next-closed-* 2>/dev/null || true
git push origin --delete <該当リモートブランチ> 2>/dev/null || true
```
