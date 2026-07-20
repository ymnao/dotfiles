# eval: pr — 統合 issue 経路 (gh stub、body 残留検証)

`/pr` step 4 の (b) 統合 issue 起票経路が仕様どおりに機能することを、
gh stub を使って呼び出し回数・body 内容・一時ファイル残留の観点で
検証する。成功系と失敗系の 2 サブケース。

## Setup (両サブケース共通)

```bash
set -o pipefail
git checkout main
branch="feature/eval-pr-consolidated-$(date +%s)"
git checkout -b "$branch"
printf 'export const sub = (a, b) => a - b\n' >> src/util.js
git add src/util.js && git commit -m "feat: sub 関数を追加"

stub_bin=$(mktemp -d)
cp $HOME/development/important/dotfiles/claude/skills/pr/evals/fixtures/stubs/gh "$stub_bin/gh"
chmod +x "$stub_bin/gh"
export EVAL_LOG_DIR=$(mktemp -d)
export PATH="$stub_bin:$PATH"

# 一時 body ファイル残留を検出するため TMPDIR 前後 snapshot
tmpdir_snapshot_before=$(mktemp)
find "$TMPDIR" -maxdepth 1 -name 'pr-issue-body-*' 2>/dev/null | sort > "$tmpdir_snapshot_before"

transcript=$(mktemp)
trap 'rm -f "$transcript" "$tmpdir_snapshot_before"; rm -rf "$stub_bin" "$EVAL_LOG_DIR"' EXIT INT TERM

stub=$HOME/development/important/dotfiles/claude/skills/pr/evals/fixtures/reviewer-stubs/09-consolidated.md
```

## Prompt (共通)

```
/pr を実行して。reviewer stub 契約を適用し findings は $stub とみなす。
user checkpoint で停止した場合は分類表を提示した上で `OK` として承認扱い
にして続行してよい (本 eval は起票側の検証が目的)。stub 読込時は
「[pr/review] stub-loaded stub=<path> count=<n>」を出力。
```

## サブケース A: 成功系

```bash
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

Pass criteria:
- [ ] `gh issue create` 呼び出し **1 回のみ** (同根 3 件 → 統合):
      `[ "$(grep -c '^cmd=issue create' "$EVAL_LOG_DIR/gh-calls.log")" = "1" ]`
- [ ] 起票 body に F1 / F2 / F3 全てが列挙されている:
      ```bash
      body=$(ls "$EVAL_LOG_DIR/bodies/"* 2>/dev/null | head -1)
      [ -n "$body" ] && grep -q 'F1' "$body" && grep -q 'F2' "$body" && grep -q 'F3' "$body"
      ```
- [ ] issue title に shell メタ文字が含まれない
      (`gh-calls.log` から `issue create` 直後の `argv[N]=--title` 値を抽出):
      ```bash
      title=$(awk '/^cmd=issue create/ {f=1; next} /^cmd=/ {f=0} f && prev=="--title" {print; exit} f {prev=$0}' \
              "$EVAL_LOG_DIR/gh-calls.log" | sed 's/^argv\[[0-9]*\]=//')
      # 空でなく、`, ", $, \, $() を含まない
      [ -n "$title" ] && ! printf '%s' "$title" | LC_ALL=C grep -qE '[`"$\\]|\$\('
      ```
- [ ] 一時 body ファイル残留なし:
      ```bash
      after=$(find "$TMPDIR" -maxdepth 1 -name 'pr-issue-body-*' 2>/dev/null | sort)
      [ "$(cat "$tmpdir_snapshot_before")" = "$after" ]
      ```
- [ ] `gh pr create` 1 回、`--draft` 含まれない (draft 判定 bullet 3 相当)

## サブケース B: 失敗系 (`gh issue create` が失敗)

```bash
GH_STUB_FAIL='issue create' env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

Pass criteria:
- [ ] `gh issue create` が >=1 回試みられ全て exit 1 (stub 失敗注入)
- [ ] draft 判定 bullet 2 発火 → `gh pr create` の argv に `--draft` 含まれる
- [ ] **失敗経路でも** 一時 body ファイル残留なし
      (finding 内容の残留防止、SKILL.md:47「起票完了後 (成功・失敗とも) に
      一時 body ファイルは rm で削除する」の遵守):
      ```bash
      after=$(find "$TMPDIR" -maxdepth 1 -name 'pr-issue-body-*' 2>/dev/null | sort)
      [ "$(cat "$tmpdir_snapshot_before")" = "$after" ]
      ```

## 共通 Pass criteria

- [ ] stub 読込ログが出た
- [ ] codex-review / code-reviewer / fable サブエージェント未起動

## Cleanup

```bash
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
```
