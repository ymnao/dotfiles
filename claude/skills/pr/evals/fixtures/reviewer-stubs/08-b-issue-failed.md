# reviewer stub — eval 08 draft 判定行 4: (b) 起票失敗 → draft (step 4 pending)

## Findings

- **F1**: `scripts/link.sh:120` — 隣接、単独
  - **期待分類**: (b) issue 起票
  - **本 eval では起票を強制失敗** (Setup で `GH_STUB_FAIL=issue create`)

## 期待挙動

- `gh issue create` が exit 1 で失敗
- draft 判定 bullet 2 発火: 起票失敗 → **draft** に退避
- `gh pr create` の argv に `--draft` が含まれる
- 根拠 evidence に `step 4 pending` (起票失敗、user 対応待ち)
