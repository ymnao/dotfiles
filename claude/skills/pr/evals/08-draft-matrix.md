# eval: pr — draft 判定表駆動 (4 行)

`/pr` step 4 の draft 判定 4 bullets が仕様どおりに動くことを、
reviewer stub と gh stub を組み合わせて 4 行の表として検証する。

判定行 (対応する stub と設定):

| # | 条件 | stub fixture | GH_STUB_FAIL | 期待判定 |
|---|---|---|---|---|
| 1 | (a) 未 fix 残存 | `08-a-remaining.md` | (なし) | **draft** |
| 2 | (b) 起票済 + (c) 混在 | `08-b-issued-plus-c.md` | (なし) | **normal** |
| 3 | (c) のみ | `08-c-only.md` | (なし) | **normal** |
| 4 | (b) 起票失敗 | `08-b-issue-failed.md` | `issue create` | **draft** (step 4 pending) |

## Setup (全行共通)

[`README.md#eval-setup`](README.md#eval-setup) の共通 snippet を貼る
(`BRANCH_SUFFIX=draft`)。行ごとに `stub` と `GH_STUB_FAIL` を差し替える。

## Prompt (共通)

```
/pr を実行して。reviewer stub 契約を適用し findings は $stub とみなす
(README.md#reviewer-stub-contract)。user checkpoint で停止した場合は
分類表を提示した上で `OK` として承認扱いにして続行してよい (本 eval は
draft/normal 判定側の検証が目的で、checkpoint 停止側は 07 で検証済)。
stub 読込時は「[pr/review] stub-loaded stub=<path> count=<n>」を出力。
```

### 判定行 1: (a) 残存 → draft

```bash
stub=$DOTFILES_ROOT/claude/skills/pr/evals/fixtures/reviewer-stubs/08-a-remaining.md
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

Pass criteria:
- [ ] `gh pr create` の argv に `--draft` が含まれる:
      `awk '/^cmd=pr create/ {f=1; next} /^cmd=/ {f=0} f && /^argv\[[0-9]+\]=--draft$/ {found=1} END {exit found?0:1}' "$EVAL_LOG_DIR/gh-calls.log"`
- [ ] transcript / PR body evidence に (a) 未 fix 残存を示す draft 判定
      根拠 marker `step 4` (bare、`step 4 pending` は (b) 起票失敗時のみ、
      [`README.md#stub-contracts`](README.md#stub-contracts) 参照)。
      境界パターンは em-dash / ASCII hyphen / 行末 / 空白いずれも許容:
      `grep -qE 'step 4([[:space:]]*[—–-]|[[:space:]]*$|,|:)' "$transcript"`

### 判定行 2: (b) 起票済 + (c) → normal

```bash
stub=$DOTFILES_ROOT/claude/skills/pr/evals/fixtures/reviewer-stubs/08-b-issued-plus-c.md
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

Pass criteria:
- [ ] `gh issue create` 1 回 (F1 の (b) 起票):
      `[ "$(grep -c '^cmd=issue create' "$EVAL_LOG_DIR/gh-calls.log")" = "1" ]`
- [ ] `gh pr create` の argv に `--draft` が **含まれない**:
      `! awk '/^cmd=pr create/ {f=1; next} /^cmd=/ {f=0} f && /^argv\[[0-9]+\]=--draft$/ {found=1} END {exit found?0:1}' "$EVAL_LOG_DIR/gh-calls.log"`
- [ ] transcript / PR body に「追跡しない (user 指示:」が出現 ((c) 記録)
- [ ] draft 判定根拠 marker `step 4 dismiss` が記録:
      `grep -qF 'step 4 dismiss' "$transcript"`
- [ ] `defer(未起票)` marker は body に **出現しない**:
      `! grep -q 'defer(未起票)' "$transcript"`

### 判定行 3: (c) のみ → normal

```bash
stub=$DOTFILES_ROOT/claude/skills/pr/evals/fixtures/reviewer-stubs/08-c-only.md
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

Pass criteria:
- [ ] `gh issue create` 0 回
- [ ] `gh pr create` に `--draft` 含まれない
- [ ] transcript に「追跡しない (user 指示:」出現
- [ ] draft 判定根拠 marker `step 4 dismiss` が記録:
      `grep -qF 'step 4 dismiss' "$transcript"`
- [ ] `defer(未起票)` marker は body に出現しない

### 判定行 4: (b) 起票失敗 → draft (step 4 pending)

```bash
stub=$DOTFILES_ROOT/claude/skills/pr/evals/fixtures/reviewer-stubs/08-b-issue-failed.md
GH_STUB_FAIL='issue create' env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

Pass criteria:
- [ ] `gh issue create` が >=1 回試みられ、いずれも stub の失敗注入で exit 1
      (skill 側は失敗を検知して draft 判定 bullet 2 に落ちる):
      `[ "$(grep -c '^cmd=issue create' "$EVAL_LOG_DIR/gh-calls.log")" -ge 1 ]`
- [ ] `gh pr create` の argv に `--draft` 含まれる
- [ ] transcript / PR body に `step 4 pending` marker 記録:
      `grep -qF 'step 4 pending' "$transcript"`

## 共通 Pass criteria (全行)

- [ ] stub 読込ログが出た:
      `grep -q '^\[pr/review\] stub-loaded' "$transcript"`
- [ ] codex-review / code-reviewer / fable サブエージェント未起動

## Cleanup

[`README.md#eval-cleanup`](README.md#eval-cleanup) 参照。
