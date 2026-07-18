# eval: next — HANDOFF.md の恒久メモ節 (「次セッション持ち越しメモ」等) を保持する

## Setup
毎回 fresh に merged 済み PR + 恒久メモ節を含む HANDOFF.md fixture を
再現する (auto-delete 環境に依存しない)。HANDOFF.md fixture は
`fixtures/handoff-template.md` に「次セッション持ち越しメモ」節と
`#999` 参照を含めて配置してある。

```bash
git checkout main && git pull
branch="feature/eval-next-handoff-notes-$(date +%s)"
git checkout -b "$branch"
echo x >> README.md && git commit -am "chore: eval-next handoff-notes fixture"
git push -u origin HEAD
gh pr create --fill
gh pr merge --merge --admin   # feature commit が main の祖先になるよう merge commit を使う
                              # (--squash だと後段の `git branch -d` が拒否される)
# `gh pr merge` は local HEAD を動かさないので $branch のまま。
[ -f HANDOFF.md ] && mv HANDOFF.md HANDOFF.md.bak
cp claude/skills/next/evals/fixtures/handoff-template.md HANDOFF.md
```

## Prompt
/next を実行して

## Pass criteria (全項目 AND)
- [ ] step 5 の /handoff 実行後も HANDOFF.md の「次セッション持ち越しメモ」
      節が残っている (`grep -F "次セッション持ち越しメモ" HANDOFF.md` がヒット)
- [ ] 節内の各項目 (codex-review 閾値 / #999) が消えていない
      (`grep -F "codex-review" HANDOFF.md` と `grep -F "#999" HANDOFF.md` の
      両方がヒット)
- [ ] HANDOFF.md がコミットされていない (`git status` に現れず、
      `git log` に HANDOFF.md 変更がない)

## Cleanup
```bash
rm -f HANDOFF.md
[ -f HANDOFF.md.bak ] && mv HANDOFF.md.bak HANDOFF.md
git checkout main 2>/dev/null || true
git branch -D "$branch" 2>/dev/null || true
git push origin --delete "$branch" 2>/dev/null || true
```
