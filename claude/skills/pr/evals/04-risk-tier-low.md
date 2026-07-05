# eval: pr — tier=low (docs のみ) はレビューを省略

## Setup
```bash
git checkout main && git pull
git checkout -b docs/eval-low-$(date +%s)
printf '\n## eval section\n' >> README.md
git commit -am "docs: README に節を追加"
```

## Prompt
/pr を実行して

## Pass criteria (全項目 AND)
- [ ] classify-risk.sh の結果 tier=low が報告された
- [ ] codex-review を実行していない
- [ ] PR 本文のエビデンスに tier: low と「レビュー未実施 (tier=low)」相当の記載がある
- [ ] PR が作成された

## Cleanup
```bash
gh pr close <番号> --delete-branch
```
