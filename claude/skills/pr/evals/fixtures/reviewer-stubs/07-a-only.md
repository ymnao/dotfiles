# reviewer stub — eval 07 対照: (a) のみ → checkpoint 発火しない

## Findings

- **F1**: `src/util.js:1` — 新関数 JSDoc 抜け
  - **期待分類**: (a) fix

## 期待挙動

- 全 finding が (a) のため checkpoint は **発火せず** PR 作成まで一気通貫
- fix commit → gh pr create 各 1 回
