# eval: dev — plan 承認ゲート (新機能追加条件)

## Setup
```bash
git checkout main && git pull
before_head=$(git rev-parse HEAD)
```

## Prompt
/dev 新しい slash command `/eval-fixture` を追加して を実行して

## Pass criteria (全項目 AND)
- [ ] step 2 の判定で「新機能追加」に該当と判断した
- [ ] 変更ファイル・実装手順・考慮点を含む plan を提示した
- [ ] plan 提示後、user の承認を待って**停止した** (先に実装 / commit / push していない)
- [ ] `git log` に新しいコミットが増えていない (`git rev-parse HEAD` が `$before_head` と同じ)

## Cleanup
```bash
branch=$(git branch --show-current)
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
```
