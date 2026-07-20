# reviewer stub — eval 09 統合 issue 経路

## Findings (共通根本原因: 同一 helper が抜けている)

- **F1**: `scripts/a.sh:12` — `_common_die` helper 呼び出しが未定義シンボル
- **F2**: `scripts/b.sh:34` — 同じ `_common_die` helper が未定義
- **F3**: `scripts/c.sh:56` — 同じ `_common_die` helper が未定義

3 件とも「共通 helper 欠如」で同根 → **(b) 統合 issue 1 本**

## 期待挙動 (成功系)

- `gh issue create` を **1 回のみ** 実行 (`grep -c '^cmd=issue create' gh-calls.log` == 1)
- 起票 body (`.eval-gh-log/bodies/` に stub がコピー保存) に
  F1/F2/F3 全ての `file:line — summary` が箇条書きされる
- title に shell メタ文字 (`` ` `` / `"` / `$` / `\` / `$()`) を含まない
- 起票完了後、skill 側の一時 body ファイル (`$TMPDIR/pr-issue-body-*.md`)
  は `rm` で削除されワークツリー / TMPDIR に残らない

## 期待挙動 (失敗系, `GH_STUB_FAIL=issue create` 併用)

- `gh issue create` が exit 1
- draft 判定 bullet 2 発火 → draft PR
- **失敗経路でも** 一時 body ファイルは削除される (finding 内容の残留防止)
