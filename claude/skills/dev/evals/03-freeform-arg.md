# eval: dev — 自由文タスク

## Setup
`teh` typo を含む README fixture を配置する。

```bash
git checkout main && git pull
[ -f README.md ] && cp README.md README.md.bak
cp claude/skills/dev/evals/fixtures/readme-typos.md README.md
```

## Prompt
/dev README の typo `teh` を `the` に直して を実行して

## Pass criteria (全項目 AND)
- [ ] 引数の自由文をそのままタスクとして受け付けた (issue 取得や
      HANDOFF 参照をしていない)
- [ ] `fix/` 系のブランチを作成した (`git branch --show-current` で確認)
- [ ] typo 修正は自明タスクなので plan 承認で停止せず実装に進んだ
      (plan は 1-3 行の提示のみ)

## Cleanup
```bash
branch=$(git branch --show-current)
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
rm -f README.md
[ -f README.md.bak ] && mv README.md.bak README.md
```
