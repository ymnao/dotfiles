# eval: dev — 引数なし (HANDOFF.md 継続)

## Setup
sandbox clone 内で main、clean tree にする。`fooo` typo を含む README
fixture は sandbox main に commit する (未 commit のまま cp すると
`/dev` の dirty-worktree 停止チェックが先に発火し、HANDOFF-継続経路の
検証にならないため)。HANDOFF.md は gitignored なのでコミットされない。

```bash
git checkout main && git pull
[ -f HANDOFF.md ] && mv HANDOFF.md HANDOFF.md.bak
cp claude/skills/dev/evals/fixtures/readme-typos.md README.md
git add README.md
git commit -m "chore: eval fixture (dev/02 sandbox)"
cat > HANDOFF.md <<'EOF'
# HANDOFF

## 次にやること (優先順)
1. eval-fixture: README の typo 修正 (`fooo` → `foo`)
2. ダミー: あとで
EOF
```

## Prompt
/dev を実行して

## Pass criteria (全項目 AND)
- [ ] HANDOFF.md を読み、最優先タスク (README typo 修正) を対象に選んだ
- [ ] 該当タスクのブランチを作成した (main のままではない、ブランチ名は
      `git branch --show-current` で確認可能)
- [ ] HANDOFF.md はコミットされていない (`git check-ignore HANDOFF.md`
      がヒットし、`git log --all -- HANDOFF.md` が空)
- [ ] step 2 の判定 (typo 修正は自明 → 停止せず実装) に進んだ

## Cleanup
```bash
branch=$(git branch --show-current)
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
git fetch origin main
git checkout -B main origin/main   # fixture commit を巻き戻す (main を origin に合わせる)
rm -f HANDOFF.md
[ -f HANDOFF.md.bak ] && mv HANDOFF.md.bak HANDOFF.md
```

(HANDOFF.md が空 / 曖昧なケースの stop 挙動は 02 の scope 外。別 eval
`02b-no-arg-empty-handoff.md` として追加起票する)
