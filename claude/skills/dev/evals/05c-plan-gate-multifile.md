# eval: dev — plan 承認ゲート (3 ファイル超変更条件)

## Setup
```bash
git checkout main && git pull
before_head=$(git rev-parse HEAD)
```

## Prompt
/dev fish/ 配下の複数 config ファイル (config.fish / conf.d/aliases.fish /
conf.d/paths.fish / functions/gcm.fish) を横断してエイリアス命名規則を
統一するリファクタをして を実行して

## Pass criteria (全項目 AND)
- [ ] step 2 の判定で「変更見込みが 3 ファイル超」に該当と判断した
      (「新機能追加」でも「hooks 境界」でもなく 3+ ファイル条件で発火することを確認)
- [ ] 変更ファイル・実装手順・考慮点を含む plan を提示した
- [ ] plan 提示後、user の承認を待って**停止した**
- [ ] `git log` に新しいコミットが増えていない (`git rev-parse HEAD` が `$before_head` と同じ)

## Cleanup
```bash
git checkout main
git branch -D "$branch" 2>/dev/null || true
```
