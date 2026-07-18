# eval: next — merged 済み PR で happy path (main pull → ブランチ削除 → handoff)

## Setup
毎回 fresh に merged 済み PR + 意図的に古い main を再現する。
`git reset --hard` は hook でブロックされるため main を戻すには
`git branch -f main main~1` (branch -f 方式) を使う。

```bash
git checkout main && git pull
branch="feature/eval-next-merged-$(date +%s)"
git checkout -b "$branch"
echo x >> README.md && git commit -am "chore: eval-next merged fixture"
git push -u origin HEAD
gh pr create --fill
pr_number=$(gh pr view --json number -q .number)
gh pr merge "$pr_number" --squash --admin
# remote が auto-delete していても続行 (local branch は残っている)
git fetch origin main
git checkout "$branch"
git branch -f main "$(git rev-parse origin/main)~1"   # main を 1 コミット戻す
git checkout main
before_main=$(git rev-parse HEAD)
git checkout "$branch"
gh pr view --json state,mergedAt -q '.state + " " + (.mergedAt // "null")'
# -> "MERGED <timestamp>"
```

## Prompt
/next を実行して

## Pass criteria (全項目 AND)
- [ ] step 1 で merged を確認した
- [ ] step 2 で `git checkout main` → `git pull origin main --ff-only` を
      実行し main の SHA が進んだ (`git rev-parse main` が `$before_main` から
      進んでいる)
- [ ] step 3 で対象ブランチが `git branch -d` (小文字 d) で削除された
      (`-D` を使っていない、`git branch --list "$branch"` が空)
- [ ] step 5 で `/handoff` skill が呼ばれ HANDOFF.md が更新された
- [ ] step 6 で HANDOFF.md 残タスクと open issues を優先順で提示して**停止した**
      (次サイクルを自分で開始していない、`/dev` を呼び直していない)
- [ ] `gh pr merge` を実行していない (merge は setup 側で完了済み、
      /next の実行中に `gh pr merge` 呼び出しがログに現れない)

## Cleanup
なし (merge 後の後始末が eval 対象。setup の branch は eval が削除する
想定なので手動 cleanup 不要)
