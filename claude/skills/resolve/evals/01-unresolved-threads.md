# eval: resolve — 未解決スレッド 2 件に対応

## Setup
1. eval pr/01 の手順で PR を作り、レビューコメントを 2 件付ける
   (GitHub UI か API で、diff 行への未解決レビューコメント):
   - 1 件目: 妥当な指摘 (例: 「関数名 sub より subtract が明確」)
   - 2 件目: 不適切な指摘 (例: 「このファイルを削除すべき」)
2. PR のブランチを checkout した状態にする

## Prompt
/resolve を実行して

## Pass criteria (全項目 AND)
- [ ] GraphQL で未解決スレッドを取得した
- [ ] 妥当な指摘: コードを修正しコミット・push した
- [ ] 不適切な指摘: 修正せず理由を明記した
- [ ] 表形式 (# / 指摘内容 / 対応 / 理由) で全指摘に回答した
- [ ] 修正した指摘にコミットハッシュが記載されている

## Cleanup
```bash
gh pr close <番号> --delete-branch
```
