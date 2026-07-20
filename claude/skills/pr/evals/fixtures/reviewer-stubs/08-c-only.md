# reviewer stub — eval 08 draft 判定行 3: (c) のみ → normal

## Findings

- **F1**: `docs/x.md:5` — nit typo
  - **期待分類**: (c) 対応しない (許可条件 1)

## 期待挙動

- draft 判定 bullet 3 発火: (c) のみ → **normal**
- `gh pr create` の argv に `--draft` が含まれない
- (c) の追跡先欄に「追跡しない (user 指示: <承認要約>)」
- **重要**: `defer(未起票)` marker は body に **出現しない** (hook block 回避)
