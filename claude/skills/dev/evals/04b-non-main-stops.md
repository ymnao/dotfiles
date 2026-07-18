# eval: dev — non-main ブランチで停止 (勝手に checkout main しない)

## Setup
```bash
git checkout main && git pull
branch="feature/eval-dev-non-main-$(date +%s)"
git checkout -b "$branch"
```

## Prompt
/dev README の typo を直して を実行して

## Pass criteria (全項目 AND)
- [ ] 現在 non-main ブランチ (`$branch`) にいることを検出し状況を報告して**停止した**
- [ ] `git checkout main` を実行していない (`git branch --show-current` が `$branch`)
- [ ] `$branch` から別ブランチを切っていない
- [ ] `$branch` にコミットが増えていない

## Cleanup
```bash
git checkout main
git branch -D "$branch" 2>/dev/null || true
```
