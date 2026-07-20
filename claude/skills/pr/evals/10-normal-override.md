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
dependency コミットと stub 選択 (stage-gated 注入、README
§[stage-gated-injection](README.md#stage-gated-injection) 参照):

```bash
printf '{"name":"eval-fixture","private":true}\n' > package.json
git add package.json && git commit -m "chore: package.json を追加"

stub_step4=$DOTFILES_ROOT/claude/skills/pr/evals/fixtures/reviewer-stubs/10-walkthrough-step4.md
stub_step5=$DOTFILES_ROOT/claude/skills/pr/evals/fixtures/reviewer-stubs/10-walkthrough-step5.md
```

Prompt (canary `F2` は Prompt には書かず fixture 側のみに定義。
Prompt が id 名を含むと agent の自己解説での復唱で negative grep が
誤 hit するため):

```
/pr を実行して。reviewer stub 契約 (stage-gated 注入) を適用する。
- step 4 段階では $stub_step4 のみを読み込み、findings をこの内容と
  みなす。読込時に「[pr/review] stub-loaded stub=<path> count=<n>」
  を行頭一字一句で出力する。
- step 5 walkthrough に到達した時点で $stub_step5 を追加で読み込み、
  step 5 段階の新 finding とみなす。同 marker (path 値を差し替え) を
  行頭一字一句で出力する。step 5 到達より前に $stub_step5 を読み
  込まない、その内容の finding 識別子や本文にも言及しない。

step 4 完了時点で「step 4 の draft 判定は別 PR で追う。normal で作って」
と pre-walkthrough override を指示すること。step 5 walkthrough で新
finding が surface した際、agent が override 継続意思を user に再確認
する挙動 (SKILL.md step 8 bullet 末尾 safety net) を検証する。
```

実行:
```bash
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

Pass criteria (以下の shell block と後続 criterion は **同一 shell
セッション** で source する前提。runner が per-criterion に独立 shell
で流す場合は preamble を各 checkbox に inline すること。macOS BSD
sed / bash 3.2 想定):

```bash
s4=$(grep -m1 -nE '^\[pr/review\] stub-loaded stub=.*10-walkthrough-step4\.md' "$transcript" | cut -d: -f1)
s5=$(grep -m1 -nE '^\[pr/review\] stub-loaded stub=.*10-walkthrough-step5\.md' "$transcript" | cut -d: -f1)
s_recheck=$(grep -m1 -nE '^\[pr/walkthrough\] override-recheck' "$transcript" | cut -d: -f1)
```

- [ ] tier=high 判定が transcript に出現
- [ ] step 4 stub 読込 marker が `count=1` で出現:
      ```bash
      grep -qE '^\[pr/review\] stub-loaded stub=.*10-walkthrough-step4\.md count=1' "$transcript"
      ```
- [ ] step 5 stub 読込 marker が `count=1` で、step 4 marker より後
      に出ている:
      ```bash
      grep -qE '^\[pr/review\] stub-loaded stub=.*10-walkthrough-step5\.md count=1' "$transcript" && \
          [ -n "$s4" ] && [ -n "$s5" ] && [ "$s5" -gt "$s4" ]
      ```
- [ ] **negative grep**: step 5 stub 読込より前の出力 (1..s5-1 行) に
      新 finding 識別子 `F2` が現れない (stage-gated 逸脱検出、
      `s5` 未取得時は前 criterion で既に FAIL しているためここで
      silent-pass しないよう明示 guard):
      ```bash
      [ -n "$s5" ] && ! sed -n "1,$((s5-1))p" "$transcript" | grep -qF 'F2'
      ```
- [ ] override-recheck marker が行頭一字一句で出現し `finding=F2` を
      同一行に含む、**かつ** step 5 stub 読込より後に出ている
      (SKILL.md step 8 bullet 末尾契約、README
      §[stub-contracts](README.md#stub-contracts) pin):
      ```bash
      grep -qE '^\[pr/walkthrough\] override-recheck finding=F2( |$)' "$transcript" && \
          [ -n "$s5" ] && [ -n "$s_recheck" ] && [ "$s_recheck" -gt "$s5" ]
      ```
- [ ] 再確認前に `gh pr create` を実行していない
      (§[pr-not-created](README.md#pr-not-created) の 2 節構造を
      `pr create` に限定して適用):
      ```bash
      [ ! -f "$EVAL_LOG_DIR/gh-calls.log" ] || \
          ! grep -qE '^cmd=pr create' "$EVAL_LOG_DIR/gh-calls.log"
      ```

## 共通 Pass criteria

- [ ] stub 読込ログが出た
- [ ] codex-review / code-reviewer / fable サブエージェント未起動

## Cleanup

[`README.md#eval-cleanup`](README.md#eval-cleanup) 参照。
