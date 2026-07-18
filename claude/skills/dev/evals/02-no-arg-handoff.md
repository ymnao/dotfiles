# eval: dev — 引数なし (HANDOFF.md 継続)

## Setup
sandbox clone 内で main、clean tree にする。HANDOFF.md fixture と、
`fooo` typo を含む README fixture を配置する (HANDOFF.md は gitignored
なのでコミットされない)。

```bash
git checkout main && git pull
[ -f HANDOFF.md ] && mv HANDOFF.md HANDOFF.md.bak
[ -f README.md ] && cp README.md README.md.bak
cp claude/skills/dev/evals/fixtures/readme-typos.md README.md
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
rm -f HANDOFF.md README.md
[ -f HANDOFF.md.bak ] && mv HANDOFF.md.bak HANDOFF.md
[ -f README.md.bak ] && mv README.md.bak README.md
```

## 関連 eval
HANDOFF.md が空 / 曖昧なケース (user 確認で停止) は別 eval に分離する
検討中。現状は自明タスク経路のみをカバーする。
