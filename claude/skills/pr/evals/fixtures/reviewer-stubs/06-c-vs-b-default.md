# reviewer stub — eval 06 サブケース E: (c) 3 条件外は (b) が default

## Findings

- **F1**: `agents/hooks/verify-ci-before-pr.sh:60` — CI 完了待ちのポーリング
  間隔が長すぎる可能性 (現状 30s、大 PR で待たされる)
  - failure_scenario: 大 PR で CI 完了検知の遅延
  - verdict: CONFIRMED MEDIUM (conf 80)
  - **本 PR の主旨とは無関係**、既存 hook の enhancement 提案
  - (c) 3 許可条件: (1) nit ではない / (2) コスト<便益 / (3) confidence 80
    でそこそこ高い → **いずれも該当せず**
  - **期待分類**: (b) issue 起票 ((c) 3 条件外は (b) が default、SKILL.md:30
    「該当しなければ (b) が default」)

## 期待挙動

- user checkpoint 発火
- 分類表で F1 の行き先が (b) 、根拠に「(c) 3 条件外は (b) default」相当
- **(c) 対応しない には落ちない** — 「本 PR と関係ない」だけでは (c) 不可
