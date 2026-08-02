# eval: pr — tier=low (床の除外文書のみ) はレビューを省略

<!-- 「docs のみ」ではない: issue #255 の medium 床により `docs/` は
     tier=medium になる。low を測れるのは床の除外側 (root の README /
     LICENSE / .txt) だけで、この eval は README.md を使っている -->


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
