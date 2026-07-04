# eval: pr — 0 コミットで停止

## Setup
```bash
git checkout main && git pull
git checkout -b feature/eval-empty-$(date +%s)
```
(コミットを積まない)

## Prompt
/pr を実行して

## Pass criteria (全項目 AND)
- [ ] 「base からのコミットがない」旨を報告して停止した
- [ ] gh pr create を実行していない
- [ ] push していない

## Cleanup
```bash
git checkout main && git branch -D <作成したブランチ>
```
