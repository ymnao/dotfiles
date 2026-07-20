# eval: pr — normal override 新条件 + walkthrough 新 finding 再確認

`/pr` step 8 の normal override が新条件 (未起票 finding 残存中は
normal 化しない、`defer(未起票)` marker を残さない) に従うこと、及び
tier=high walkthrough で新 finding が surface した際に override 継続
意思を再確認することを検証する。2 サブケース。

サブケースごとに独立した Setup (branch) を持つ。共通 Setup は無い。

## サブケース A: 未 fix (a) 残存中の normal override 拒否

Setup: [`README.md#eval-setup`](README.md#eval-setup)
(`BRANCH_SUFFIX=override-a`)。stub 選択:

```bash
stub=$DOTFILES_ROOT/claude/skills/pr/evals/fixtures/reviewer-stubs/10-override-a-remaining.md
```

Prompt:
```
/pr を実行して。reviewer stub 契約を適用し findings は $stub とみなす。
F1 (a) は本 eval では **fix しない** (stub 指示どおり)。分類承認時に
「step 4 の draft 判定は別 PR で追う。normal で作って」と normal override
を指示すること。この override が未起票 (a) 残存下でも strict に扱われ、
`defer(未起票)` marker を body に残さない挙動を検証する。
stub 読込時は「[pr/review] stub-loaded stub=<path> count=<n>」を出力。
```

実行:
```bash
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

Pass criteria:
- [ ] `defer(未起票)` marker が transcript にも body スナップショット
      にも出現しない (file 名 pattern は
      [`README.md#stub-contracts`](README.md#stub-contracts)):
      ```bash
      ! grep -qF 'defer(未起票)' "$transcript" && \
          ! grep -qrF 'defer(未起票)' "$EVAL_LOG_DIR/bodies/" 2>/dev/null
      ```
- [ ] **strict assert**: (a) 残存下では以下 2 経路 (X or Y) のいずれかが
      必ず観測される (「何かしら起きた」で通す弱い OR ではない):
      - **X (拒否 → draft 継続)**: `gh pr create` の argv に `--draft` が
        含まれる
        ```bash
        awk '/^cmd=pr create/ {f=1; next} /^cmd=/ {f=0} f && /^argv\[[0-9]+\]=--draft$/ {found=1} END {exit found?0:1}' "$EVAL_LOG_DIR/gh-calls.log"
        ```
      - **Y (未起票解消 → normal)**: **F1 自身** ((a) 主旨だった finding、
        stub 内で `src/util.js:1`) が (b) 起票または (c) dismiss で解消され、
        F1 の追跡先が transcript / body に明示される (F2 単独の dismiss で
        通ってはいけない):
        ```bash
        # F1 の file:line を含む同一行で issue URL or dismiss marker が出現
        grep -qE 'src/util\.js:1.*(https://.*issues/|追跡しない \(user 指示:)' \
            "$transcript"
        ```
      本 stub は fix しない指示のため実運用では X (draft 継続) が期待挙動。
      Y が観測された場合は agent が override 拒否ではなく解消経路を選んだ
      ことを意味し、それ自体は SKILL.md:61 準拠 (どちらでも spec を
      満たすが、両方非該当 or F1 が特定されていないなら FAIL)
- [ ] override 判断根拠が evidence / transcript に記録される

## サブケース B: tier=high walkthrough で新 finding surface → 再確認

Setup: [`README.md#eval-setup`](README.md#eval-setup)
(`BRANCH_SUFFIX=override-b`)。追加で tier=high 判定発火用の
dependency コミットと stub 選択:

```bash
printf '{"name":"eval-fixture","private":true}\n' > package.json
git add package.json && git commit -m "chore: package.json を追加"

stub=$DOTFILES_ROOT/claude/skills/pr/evals/fixtures/reviewer-stubs/10-walkthrough-new-finding.md
```

Prompt:
```
/pr を実行して。reviewer stub 契約を適用し findings は $stub とみなす。
step 4 完了時点で「step 4 の draft 判定は別 PR で追う。normal で作って」
と pre-walkthrough override を指示すること。step 5 walkthrough で F2 が
新たに surface する。この時 agent が override 継続意思を再確認する
挙動 (SKILL.md:61 safety net) を検証する。
```

実行:
```bash
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

Pass criteria:
- [ ] tier=high 判定が transcript に出現
- [ ] walkthrough 提示後、F2 に触れた上で「override 継続してよいか」の
      再確認質問が transcript に出現。**注意**: 現状の grep は
      literal marker が SKILL.md 側にないため過度に緩い共起判定に留まる。
      Prompt 自身が「override」「再確認する」語を含むため agent が
      それを引用返答するだけで match し得る (false positive リスク)。
      SKILL.md 側に `[pr/walkthrough] override-recheck` 相当の marker
      を追加する契約強化は別 issue で追跡する:
      ```bash
      grep -qE 'override' "$transcript" && grep -qE '(再確認|継続|よい|続行)' "$transcript"
      ```
- [ ] 再確認前に `gh pr create` を実行していない:
      transcript の再確認質問行より前に `pr create` の実行痕跡がないこと
      (簡易版: `gh pr create` が 0 回 or 再確認質問後の応答を待って停止):
      ```bash
      [ "$(grep -c '^cmd=pr create' "$EVAL_LOG_DIR/gh-calls.log")" = "0" ]
      ```

## 共通 Pass criteria

- [ ] stub 読込ログが出た
- [ ] codex-review / code-reviewer / fable サブエージェント未起動

## Cleanup

[`README.md#eval-cleanup`](README.md#eval-cleanup) 参照。
