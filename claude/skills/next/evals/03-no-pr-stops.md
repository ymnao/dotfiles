# eval: next — PR なしのブランチでは git 状態を変更せず停止する

## Setup
push もされていない・PR も無いローカルブランチを用意する。

```bash
git checkout main && git pull
git checkout -b feature/eval-next-no-pr-$(date +%s)
echo y >> README.md && git commit -am "chore: eval-next no-pr fixture"
gh pr view --json state 2>&1 | head -1   # -> エラー / no pull requests found
BEFORE_MAIN=$(git rev-parse main)
BEFORE_BRANCH=$(git branch --show-current)
```

## Prompt
/next を実行して

## Pass criteria (全項目 AND)
- [ ] `gh pr view` が「PR なし」で失敗したことを検出して**停止した**
- [ ] `git checkout main` / `git pull` を実行していない
- [ ] `git branch -d` を実行していない (`BEFORE_BRANCH` が残っている)
- [ ] main の SHA が `BEFORE_MAIN` から動いていない
- [ ] HANDOFF.md を更新していない

## Cleanup
```bash
git checkout main
git branch -D <ブランチ>
```
