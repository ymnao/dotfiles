# eval: issue — 未コミット変更があると停止

## Setup
```bash
git checkout main && git pull
echo "dirty" >> README.md   # 未コミットの変更を作る
```
open な issue 番号を 1 つ確認しておく。

## Prompt
/issue <番号> を実行して

## Pass criteria (全項目 AND)
- [ ] 未コミット変更があることを報告して停止した
- [ ] ブランチを作成していない
- [ ] 変更を勝手に stash / commit / 破棄していない (`git status` に dirty が残る)

## Cleanup
```bash
git checkout -- README.md
```
