# eval: pr — 統合 issue 経路 (gh stub、body 残留検証)

`/pr` step 4 の (b) 統合 issue 起票経路が仕様どおりに機能することを、
gh stub を使って呼び出し回数・body 内容・一時ファイル残留の観点で
検証する。成功系と失敗系の 2 サブケース。

## Setup (両サブケース共通)

[`README.md#eval-setup`](README.md#eval-setup) を貼る
(`BRANCH_SUFFIX=consolidated`)。その後、body 残留検証のため tmpdir
スナップショットと trap を拡張する:

```bash
tmpdir_snapshot_before=$(mktemp)
find "$TMPDIR" -maxdepth 1 -name 'pr-issue-body-*' 2>/dev/null | sort > "$tmpdir_snapshot_before"
trap 'rm -f "$transcript" "$tmpdir_snapshot_before"; rm -rf "$stub_bin" "$EVAL_LOG_DIR"' EXIT INT TERM

stub=$HOME/development/important/dotfiles/claude/skills/pr/evals/fixtures/reviewer-stubs/09-consolidated.md
```

body-file 命名 (`pr-issue-body-*`) は
[`README.md#stub-contracts`](README.md#stub-contracts) で contract 化。

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
- [ ] 起票 body に F1 / F2 / F3 全てが列挙されている
      (最初の body を数値順で取得):
      ```bash
      first=$(ls "$EVAL_LOG_DIR/bodies/" 2>/dev/null | sort -V | head -1)
      body="$EVAL_LOG_DIR/bodies/$first"
      [ -n "$first" ] && grep -q 'F1' "$body" && grep -q 'F2' "$body" && grep -q 'F3' "$body"
      ```
- [ ] issue title に shell メタ文字が含まれない
      (`gh-calls.log` から `issue create` 直後の `argv[N]=--title` の
      **次行** の argv 値を抽出。stub は 1 引数 1 行 `argv[i]=<value>`
      形式で記録するので、値行 `argv[N+1]=<title 本体>` から prefix を
      strip する):
      ```bash
      title=$(awk '
          BEGIN {strip="^argv\\[[0-9]+\\]="}
          /^cmd=issue create/ {f=1; next}
          /^cmd=/ {f=0}
          f {
              val=$0; sub(strip, "", val)
              if (prev == "--title") { print val; exit }
              prev = val
          }' "$EVAL_LOG_DIR/gh-calls.log")
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

[`README.md#eval-cleanup`](README.md#eval-cleanup) 参照。
