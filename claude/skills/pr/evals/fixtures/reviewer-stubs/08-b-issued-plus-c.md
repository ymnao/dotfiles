# reviewer stub — eval 08 draft 判定行 2: (b) 起票済 + (c) 混在 → normal

## Findings

- **F1**: `scripts/link.sh:120` — 隣接、単独
  - **期待分類**: (b) issue 起票 (成功、URL 取得)
- **F2**: `docs/x.md:5` — nit typo
  - **期待分類**: (c) 対応しない (許可条件 1)

## 期待挙動

- (a) 残存なし、(b) 起票済 URL あり、(c) あり
- draft 判定 bullet 3 発火: (c) がある + (a) 未 fix なし → **normal**
- `gh pr create` の argv に `--draft` が含まれない
- (c) の追跡先欄に「追跡しない (user 指示: <承認要約>)」が入る
