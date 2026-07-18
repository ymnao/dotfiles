# eval: next — open PR では git 状態を変更せず停止する

## Setup
sandbox clone 内で、対象ブランチに OPEN な PR がある状態を作る
(pr eval 01 の残りを使ってよい)。

```bash
git checkout <feature ブランチ>
gh pr view --json state -q .state   # -> "OPEN" であること
BEFORE_SHA=$(git rev-parse HEAD)
BEFORE_MAIN=$(git rev-parse main)
```

## Prompt
/next を実行して

## Pass criteria (全項目 AND)
- [ ] step 1 で `gh pr view --json state,mergedAt,url` が実行された
- [ ] state=OPEN を検出して**停止した**
- [ ] `git checkout main` を実行していない (現ブランチが変わっていない)
- [ ] `git pull` を実行していない (main の SHA が `BEFORE_MAIN` と同じ)
- [ ] `git branch -d` を実行していない (対象ブランチが残っている)
- [ ] `HANDOFF.md` が更新されていない (touched していない)

## Cleanup
なし (状態を変えていない)
