# eval: dev — 自由文タスク

## Setup
```bash
git checkout main && git pull
```

## Prompt
/dev README の typo `teh` を `the` に直して を実行して

## Pass criteria (全項目 AND)
- [ ] 引数の自由文をそのままタスクとして受け付けた (issue 取得や
      HANDOFF 参照をしていない)
- [ ] `fix/` 系のブランチを作成した
- [ ] typo 修正は自明タスクなので plan 承認で停止せず実装に進んだ
      (plan は 1-3 行の提示のみ)

## Cleanup
```bash
git checkout main
git branch -D <作成したブランチ> 2>/dev/null || true
```
