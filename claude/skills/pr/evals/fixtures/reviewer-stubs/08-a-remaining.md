# reviewer stub — eval 08 draft 判定行 1: (a) 未 fix 残存 → draft

## Findings

- **F1**: `src/util.js:1` — 主旨直結の bug
  - **期待分類**: (a) fix
  - **本 eval では apply しない** (未 fix のまま残す)

## 期待挙動

- draft 判定 bullet 1 発火: (a) 残存 → **draft** で作成
- `gh pr create` の argv に `--draft` が含まれる
- 根拠 evidence に bare `step 4` marker が記録 (a 残存の draft 化根拠。
  `step 4 pending` は (b) 起票失敗時専用で、ここでは使わない。
  詳細は `../../README.md#stub-contracts`)
