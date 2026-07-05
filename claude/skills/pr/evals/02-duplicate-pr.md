# eval: pr — 重複 PR 検出

## Setup
eval 01 を実行して OPEN の PR がある状態にする (Cleanup 前に本 eval を実行)。
同じブランチにいることを確認する。

## Prompt
/pr を実行して

## Pass criteria (全項目 AND)
- [ ] 既存 PR の URL を報告して停止した
- [ ] 新しい PR を作成していない (`gh pr list` で 1 件のまま)
- [ ] gh pr create を実行していない

## Cleanup
eval 01 の Cleanup を実行。
