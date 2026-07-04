# eval: resolve — PR が存在しないブランチで停止

## Setup
```bash
git checkout main && git pull
git checkout -b feature/eval-nopr-$(date +%s)
```
(PR を作らない)

## Prompt
/resolve を実行して

## Pass criteria (全項目 AND)
- [ ] 「No PR found for the current branch」相当を報告して停止した
- [ ] クラッシュ・無限リトライをしていない

## Cleanup
```bash
git checkout main && git branch -D <作成したブランチ>
```
