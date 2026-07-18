# eval: dev — レビューループは 2 周が上限、残 finding は /pr の fix-or-issue へ委ねる

## Setup
`review-target.sh` fixture を実装フェーズでコミットさせる。redundancies が
複数入っているので 1 周目で全て解消しきれない場合に 2 周目突入 → 2 周上限
到達の挙動が観察できる。ただし完全決定化は fixture だけでは困難なため、
Pass criteria は**挙動ベース** (cap で停止しているか / 残 finding の
記録があるか) に寄せる。完全決定化 (reviewer stub) は追跡 issue に委ねる。

```bash
git checkout main && git pull
branch="feature/eval-review-cap-$(date +%s)"
git checkout -b "$branch"
```

## Prompt
/dev claude/skills/dev/evals/fixtures/review-target.sh の内容を
tmp/review-cap-target.sh にコピーしてコミットしてから、レビューループを
回して を実行して

## Pass criteria (全項目 AND)
- [ ] レビューループは最大 2 周までしか回っていない (3 周目に入っていない)
- [ ] 2 周目まで到達しなかった場合 (1 周で findings 0) は「1 周で完了」
      と明示的にログされている (skip ではない)
- [ ] 2 周目で残った finding があれば fix せず**記録**した
      (会話ログ or PR 本文の evidence に残 finding 一覧が出る)
- [ ] step 5 で /pr を呼び、残 finding は /pr の fix-or-issue ポリシー
      (fix コミット or issue 起票) に必ず引き渡された (黙って消えていない)
- [ ] 2 周上限を超えて延々と修正を続けていない (発散防止)

## Cleanup
```bash
pr_number=$(gh pr view --json number -q .number 2>/dev/null)
git checkout main
git branch -D "$branch" 2>/dev/null || true
[ -n "$pr_number" ] && gh pr close "$pr_number" --delete-branch 2>/dev/null || true
# 起票された残 finding issue があれば手動で確認して close
```
