# reviewer stub — eval 10 normal override 新条件

## Findings

- **F1**: `src/util.js:1` — 主旨直結 (a) fix、**本 eval では apply しない**
- **F2**: `docs/x.md:5` — nit (c) 対応しない

## 期待挙動

- (a) 未 fix が残る限り、user が normal override を指示しても **normal 化しない**
  (override は draft 判定 override であって、未起票 finding 残存の hook block
  は bypass しない。marker 文字列 `defer(未起票)` を残すと deadlock)
- transcript / body に `defer(未起票)` marker が **出現しない**
- (a) 残存の解消 (fix or (b) 起票 or (c) dismiss) を経ない限り draft
