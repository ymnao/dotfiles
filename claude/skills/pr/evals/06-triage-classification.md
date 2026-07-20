# eval: pr — 分類分岐 (fix-or-issue-or-dismiss の 5 サブケース)

`/pr` step 4 の Fix-or-issue-or-dismiss ポリシー分類が仕様どおりに機能
することを、reviewer stub と gh stub を使って決定化検証する。

サブケース (対応する stub fixture):

- **A**: (a) 主旨直結のみ → checkpoint 発火せず (`06-a-only.md`)
- **B**: (b) 隣接単独 → 単独起票 (`06-b-single.md`)
- **C**: 同根 2 件以上 → 統合 issue 1 本 (`06-b-consolidated.md`)
- **D**: 同根なし複数 → 統合せず個別起票 (`06-b-not-consolidated.md`)
- **E**: (c) 3 条件外は (b) が default (`06-c-vs-b-default.md`)

**5 サブケースを 1 eval にまとめる**: fixture を差し替えて 5 回実行
する運用。個別に `06a` `06b` ... と分割すると Setup / Cleanup / Prompt
がほぼ完全に重複するため。3 回実行 3/3 PASS 基準は各サブケースごとに
独立に満たす。

## Setup (全サブケース共通)

サンドボックス repo (`skill-eval-sandbox`) の clone 内で実行
([`README.md#sandbox-repo`](README.md#sandbox-repo))。共通 Setup snippet
は [`README.md#eval-setup`](README.md#eval-setup) を貼る:
`BRANCH_SUFFIX=triage`。サブケースごとに `stub` 変数だけ差し替える:

```bash
stub=$DOTFILES_ROOT/claude/skills/pr/evals/fixtures/reviewer-stubs/06-a-only.md
```

## Prompt (全サブケース共通)

```
/pr を実行して。ただし本 eval は reviewer stub 契約
(claude/skills/pr/evals/README.md#reviewer-stub-contract) を適用する:
codex-review / fable フォールバックを実起動せず、レビュー結果として
$stub の内容を「verify 済 findings」とみなして step 4 分類に渡すこと。
stub 読込時に「[pr/review] stub-loaded stub=<path> count=<n>」を
行頭一字一句この形式で応答テキストに出力すること。
```

実行:

```bash
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<上記 Prompt>" | tee "$transcript"
```

## Pass criteria (全項目 AND、サブケースごとに独立検証)

機械検証可能:

- [ ] stub 読込ログが出た:
      `grep -qE '^\[pr/review\] stub-loaded stub=.*06-.*\.md count=[0-9]+$' "$transcript"`
- [ ] codex-review / code-reviewer / fable サブエージェント未起動
      ([`README.md#reviewer-stub-contract`](README.md#reviewer-stub-contract) の 3 grep で検証)

サブケース A (`06-a-only.md`):
- [ ] user checkpoint が **発火しない** (transcript に「分類表」提示は
      あってもよいが「承認を待つ」旨の停止表示がない)
- [ ] `gh issue create` 呼び出し 0 回:
      `[ "$(grep -c '^cmd=issue create' "$EVAL_LOG_DIR/gh-calls.log")" = "0" ]`
- [ ] `gh pr create` 呼び出し 1 回

サブケース B (`06-b-single.md`):
- [ ] user checkpoint 発火 (停止 → 承認後再開の 2 段実行、
      [`README.md#approve-and-resume`](README.md#approve-and-resume))
- [ ] 承認後 `gh issue create` 1 回:
      `[ "$(grep -c '^cmd=issue create' "$EVAL_LOG_DIR/gh-calls.log")" = "1" ]`

サブケース C (`06-b-consolidated.md`):
- [ ] user checkpoint 発火
- [ ] 承認後 `gh issue create` **1 回のみ** (同根 3 件 → 統合)
- [ ] 起票 body (`$EVAL_LOG_DIR/bodies/`) に fixture の 3 finding の
      `file:line` が全て列挙されている (stub 命名は 0-padded 連番 なので
      lexical sort が数値順と一致、`sort -V` 不要):
      ```bash
      body="$EVAL_LOG_DIR/bodies/$(ls "$EVAL_LOG_DIR/bodies/" | head -1)"
      grep -q 'claude/skills/foo/SKILL.md:12' "$body" \
          && grep -q 'claude/skills/foo/SKILL.md:35' "$body" \
          && grep -q 'claude/skills/foo/SKILL.md:47' "$body"
      ```

サブケース D (`06-b-not-consolidated.md`):
- [ ] user checkpoint 発火
- [ ] 承認後 `gh issue create` **2 回** (同根なしのため統合しない):
      `[ "$(grep -c '^cmd=issue create' "$EVAL_LOG_DIR/gh-calls.log")" = "2" ]`

サブケース E (`06-c-vs-b-default.md`):
- [ ] 分類表で F1 の行き先が (b)、根拠に「(c) 3 条件外は (b) default」
      相当の記述 (transcript grep で「(b)」「default」の共起を確認)
- [ ] 承認後 `gh issue create` 1 回 ((c) には落ちない)

transcript 判定 (human runner):
- [ ] 各サブケースの分類表内容が fixture の「期待分類」と一致する
- [ ] 統合 issue の title に shell メタ文字が含まれていない (C の body 確認時に併せて)

## Cleanup

[`README.md#eval-cleanup`](README.md#eval-cleanup) 参照。
