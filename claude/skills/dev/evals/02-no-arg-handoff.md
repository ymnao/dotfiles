# eval: dev — 引数なし (HANDOFF.md 継続)

## Setup
sandbox clone 内で main、clean tree にする。HANDOFF.md を仮に用意する
(gitignored なのでコミットされない)。既存 HANDOFF.md がある場合は退避する。

```bash
git checkout main && git pull
[ -f HANDOFF.md ] && mv HANDOFF.md HANDOFF.md.bak
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
- [ ] 該当タスクのブランチを作成した (main のままではない)
- [ ] HANDOFF.md はコミットされていない (`git check-ignore HANDOFF.md`
      がヒットし、`git log --all -- HANDOFF.md` が空)
- [ ] step 2 の判定 (typo 修正は自明 → 停止せず実装) に進んだ

## HANDOFF.md が空 / 曖昧なケース
上記 Setup で HANDOFF.md を空にした場合:
- [ ] user にタスク内容を確認して**停止した** (勝手に着手していない)

## Cleanup
```bash
rm -f HANDOFF.md
[ -f HANDOFF.md.bak ] && mv HANDOFF.md.bak HANDOFF.md
git checkout main
git branch -D "$branch" 2>/dev/null || true
```
