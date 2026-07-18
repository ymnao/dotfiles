# eval: dev — レビューループは 2 周が上限、残 finding は /pr の fix-or-issue へ委ねる

## Setup
2 周目でも新規指摘が出続けやすい変更 (複数モジュールにまたがる中規模
変更など) を用意する。無理な場合は、実行者が「2 周目で新規指摘が
残っていた」体で /pr へ引き渡すシナリオとして扱う。

```bash
git checkout main && git pull
git checkout -b "feature/eval-review-cap-$(date +%s)"
```

## Prompt
/dev 上記ブランチで中規模変更を実装し、レビューループを回して を
実行して

## Pass criteria (全項目 AND)
- [ ] レビューループは最大 2 周までしか回っていない (3 周目に入っていない)
- [ ] 2 周目で残った finding があれば fix せず**記録**した
      (会話ログ or PR 本文の evidence に残 finding 一覧が出る)
- [ ] step 5 で /pr を呼び、残 finding は /pr の fix-or-issue ポリシー
      (fix コミット or issue 起票) に必ず引き渡された (黙って消えていない)
- [ ] 2 周上限を超えて延々と修正を続けていない (発散防止)

## Cleanup
```bash
git checkout main
git branch -D <ブランチ>
gh pr close <番号> --delete-branch 2>/dev/null || true
gh issue close <起票された残 finding issue 番号があれば> 2>/dev/null || true
```
