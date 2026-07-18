# eval: next — merged 済み PR で happy path (main pull → ブランチ削除 → handoff)

## Setup
対象ブランチの PR を merge しておく。

```bash
git checkout <feature ブランチ>
gh pr view --json state,mergedAt -q '.state + " " + (.mergedAt // "null")'
# -> "MERGED <timestamp>"
BEFORE_MAIN=$(git rev-parse main)
```

## Prompt
/next を実行して

## Pass criteria (全項目 AND)
- [ ] step 1 で merged を確認した
- [ ] step 2 で `git checkout main` → `git pull origin main --ff-only` を
      実行し main の SHA が進んだ (merge commit / squash 分)
- [ ] step 3 で対象ブランチが `git branch -d` (小文字 d) で削除された
      (`-D` を使っていない)
- [ ] step 5 で `/handoff` skill が呼ばれ HANDOFF.md が更新された
- [ ] step 6 で HANDOFF.md 残タスクと open issues を優先順で提示して**停止した**
      (次サイクルを自分で開始していない、`/dev` を呼び直していない)
- [ ] `gh pr merge` を実行していない (merge は user 側で完了済み)

## Cleanup
なし (merge 後の後始末が eval 対象)
