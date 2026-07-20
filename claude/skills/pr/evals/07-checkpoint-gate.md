# eval: pr — user checkpoint 制御フロー (停止 + 副作用ゼロ + 再開)

`/pr` step 4 の user checkpoint (必須ゲート) が仕様どおりに機能する
ことを検証する。dev/05a の「plan 承認ゲート」eval と同型の停止検証に
加え、gh 副作用ゼロ + 承認後再開を検証する。

サブケース:

- **A**: (b) と (c) 混在 → **停止** (`07-b-and-c.md`)
- **B**: (a) のみ → **停止しない** (`07-a-only.md`) — 対照
- **C**: A の 1 段目で停止後、承認応答を送って再開検証
- **D**: A の 1 段目で停止後、分類修正指示を送って **再提示** される検証

## Setup (全サブケース共通)

サンドボックス repo の clone 内で実行。

```bash
set -o pipefail
git checkout main
branch="feature/eval-pr-checkpoint-$(date +%s)"
git checkout -b "$branch"
printf 'export const sub = (a, b) => a - b\n' >> src/util.js
git add src/util.js && git commit -m "feat: sub 関数を追加"
before_head=$(git rev-parse HEAD)

stub_bin=$(mktemp -d)
cp $HOME/development/important/dotfiles/claude/skills/pr/evals/fixtures/stubs/gh "$stub_bin/gh"
chmod +x "$stub_bin/gh"
export EVAL_LOG_DIR=$(mktemp -d)
export PATH="$stub_bin:$PATH"

transcript=$(mktemp)
trap 'rm -f "$transcript"; rm -rf "$stub_bin" "$EVAL_LOG_DIR"' EXIT INT TERM
```

## Prompt (共通)

```
/pr を実行して。reviewer stub 契約を適用し、レビュー findings は $stub の
内容とみなすこと (README.md#reviewer-stub-contract)。stub 読込時は
「[pr/review] stub-loaded stub=<path> count=<n>」を行頭で出力すること。
```

## サブケース A: (b)/(c) 混在で停止 + 副作用ゼロ

```bash
stub=$HOME/development/important/dotfiles/claude/skills/pr/evals/fixtures/reviewer-stubs/07-b-and-c.md
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 --output-format json -p "<Prompt>" \
    | tee "$transcript"
```

Pass criteria:
- [ ] stub 読込ログが出た:
      `grep -q '^\[pr/review\] stub-loaded' "$transcript"`
- [ ] 分類表 (行頭 `|` + `#` + `Finding` の header 行) が transcript に
      1 つ以上出現している
- [ ] user checkpoint が発火し停止した (transcript 末尾に
      「承認」「OK」「進めて」等を待つ旨の記述がある)
- [ ] **副作用ゼロ (最重要)**: `gh pr create` / `gh issue create` の
      呼び出しが 0 回:
      `[ ! -f "$EVAL_LOG_DIR/gh-calls.log" ] || ! grep -qE '^cmd=(pr|issue) create' "$EVAL_LOG_DIR/gh-calls.log"`
- [ ] HEAD が Setup 直後と同一 (fix commit も入っていない):
      `[ "$(git rev-parse HEAD)" = "$before_head" ]`
- [ ] codex-review / code-reviewer / fable サブエージェント未起動

## サブケース B: (a) のみで停止しない (対照)

```bash
stub=$HOME/development/important/dotfiles/claude/skills/pr/evals/fixtures/reviewer-stubs/07-a-only.md
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

Pass criteria:
- [ ] `gh pr create` 呼び出し 1 回:
      `[ "$(grep -c '^cmd=pr create' "$EVAL_LOG_DIR/gh-calls.log")" = "1" ]`
- [ ] `gh issue create` 呼び出し 0 回
- [ ] fix commit が新たに入っている (transcript / git log で確認)

## サブケース C: 承認後再開 (2 段実行)

サブケース A の 1 段目 (`--output-format json`) から `session_id` を取得
した後、承認を送って再開する。実行方法は
[`README.md#approve-and-resume`](README.md#approve-and-resume) 参照。

```bash
# 1 段目: 停止確認 (サブケース A と同じ)
session_id=$(env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 --output-format json -p "<Prompt>" \
    | tee "$transcript" | jq -r '.session_id')

# 2 段目: 承認送信で再開
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 --resume "$session_id" -p "OK 進めて" \
    | tee -a "$transcript"
```

Pass criteria:
- [ ] 1 段目時点で `gh (pr|issue) create` 0 回
- [ ] 2 段目後に `gh issue create` >= 1 回、`gh pr create` = 1 回:
      `[ "$(grep -c '^cmd=issue create' "$EVAL_LOG_DIR/gh-calls.log")" -ge "1" ]`
      `[ "$(grep -c '^cmd=pr create' "$EVAL_LOG_DIR/gh-calls.log")" = "1" ]`

`--resume` が想定通り動かない環境では本サブケースを SKIP と記録する
(A/B/D で停止動作の主目的は担保されている)。

## サブケース D: 分類修正指示で再提示

サブケース A の 1 段目後、「F3 は (c) にして」等の修正指示を送る。

```bash
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 --resume "$session_id" \
    -p "F3 の行き先を (c) 対応しない に変更して再提示して" \
    | tee -a "$transcript"
```

Pass criteria:
- [ ] 2 段目の応答に分類表が **再度提示** される (行頭 `|` + `Finding`
      の header 行が 2 段目部分にも出現)
- [ ] 承認前の副作用ゼロは引き続き維持
      (`grep -c '^cmd=(pr|issue) create' "$EVAL_LOG_DIR/gh-calls.log"` が 0)

## Cleanup

```bash
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
```
