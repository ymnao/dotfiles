# reviewer stub — eval 06 サブケース C: 同根 2 件以上 → 統合 issue 1 本

## Findings

- **F1**: `claude/skills/foo/SKILL.md:12` — step 2 の分岐に対応する eval が
  未整備 (共通根本原因: eval infra 欠如)
  - verdict: CONFIRMED MEDIUM (conf 90)
- **F2**: `claude/skills/foo/SKILL.md:35` — step 5 の draft 判定に対応する
  eval が未整備 (共通根本原因: eval infra 欠如)
  - verdict: CONFIRMED MEDIUM (conf 92)
- **F3**: `claude/skills/foo/SKILL.md:47` — 統合 issue 経路の fixture が
  未整備 (共通根本原因: eval infra 欠如)
  - verdict: CONFIRMED MEDIUM (conf 88)

## 期待分類

- 3 件全て (b) 統合 issue #N (同根が 2 件以上 → 1 本の統合 issue)

## 期待挙動

- user checkpoint 発火
- user 承認後: `gh issue create` を **1 回のみ** 実行
- 起票 body に F1/F2/F3 全ての file:line と要約が列挙される
