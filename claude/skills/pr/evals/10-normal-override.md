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
      ことを意味し、それ自体は SKILL.md step 8 bullet 末尾契約準拠
      (どちらでも spec を
      満たすが、両方非該当 or F1 が特定されていないなら FAIL)
- [ ] override 判断根拠が evidence / transcript に記録される

## サブケース B: tier=high walkthrough で新 finding surface → 再確認

Setup: [`README.md#eval-setup`](README.md#eval-setup)
(`BRANCH_SUFFIX=override-b`)。追加で tier=high 判定発火用の
dependency コミットと stub 選択 (stage-gated 注入、README
§[stage-gated-injection](README.md#stage-gated-injection) 参照):

```bash
# 複数行 JSON。F2 (10-walkthrough-step5.md) は package.json:2 の
# dependency 追加行を参照するため、2 行目に実在する dependency 相当
# 行を持たせる (setup が 1 行 file だと F2 の参照先が存在せず finding
# 自体が検証不能扱いになる)
cat > package.json <<'JSON'
{
  "dependencies": { "example": "1.0.0" },
  "name": "eval-fixture",
  "private": true
}
JSON
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
# marker 未出現時 grep exit 1 → pipefail で assignment failure → set -e 死。
# 各 assignment に || true を付け、後段の [ -n "$s?" ] guard 側で FAIL に倒す
s4=$(grep -m1 -nE '^\[pr/review\] stub-loaded stub=.*10-walkthrough-step4\.md' "$transcript" | cut -d: -f1) || true
s5=$(grep -m1 -nE '^\[pr/review\] stub-loaded stub=.*10-walkthrough-step5\.md' "$transcript" | cut -d: -f1) || true
s_recheck=$(grep -m1 -nE '^\[pr/walkthrough\] override-recheck finding=F2$' "$transcript" | cut -d: -f1) || true
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
- [ ] **negative grep (識別子)**: step 5 stub 読込より前の出力
      (1..s5-1 行) に新 finding 識別子 `F2` が現れない (stage-gated
      逸脱検出、`s5` 未取得時は前 criterion で既に FAIL しているため
      ここで silent-pass しないよう明示 guard。`sed | grep` パイプは
      `set -o pipefail` 下で SIGPIPE 141 が `!` 反転され silent-pass
      する余地があるため単一 awk process で範囲検査する):
      ```bash
      [ -n "$s5" ] && awk -v stop="$s5" 'NR<stop && index($0,"F2") {f=1} END {exit f}' "$transcript"
      ```
- [ ] **negative grep (本文 canary)**: step 5 stub 読込より前の出力に
      step 5 stub 本文の canary token `CANARY-STEP5-BODY` が現れない
      (識別子 `F2` だけ伏せて本文を先読み言及する実装の検出、README
      §[stub-contracts](README.md#stub-contracts) pin):
      ```bash
      [ -n "$s5" ] && awk -v stop="$s5" 'NR<stop && index($0,"CANARY-STEP5-BODY") {f=1} END {exit f}' "$transcript"
      ```
- [ ] override-recheck marker が行頭一字一句 `[pr/walkthrough]
      override-recheck finding=F2` として **単独行** で出現し
      (SKILL.md「前後に装飾を付けない」契約、行末 anchor `$` で厳密
      一致)、**かつ** step 5 stub 読込より後に出ている
      (SKILL.md `## Telemetry markers` 節、README
      §[stub-contracts](README.md#stub-contracts) pin):
      ```bash
      [ -n "$s5" ] && [ -n "$s_recheck" ] && [ "$s_recheck" -gt "$s5" ]
      ```
      (`s_recheck` は L125 で行末 `$` anchor 込みの厳密 regex で捕捉
      済み。non-empty guard = literal 一致 + 単独行が確立している)
- [ ] **override-recheck marker 直後の質問 marker (F1 契約)**:
      `override-recheck` 行の直後の最初の non-blank 行が
      `[pr/walkthrough] override-recheck-question: <質問文>` の形式で
      出現する (marker を出しただけで質問せず停止する実装を検出、
      blank 行の挟み込みは可、質問文は非空、SKILL.md
      `## Telemetry markers` 節 pin。awk single-process で
      `override-recheck` 行検出後 `NF` の最初の行だけを抽出し、その
      内容を prefix + 非空引数で厳密検査):
      ```bash
      [ -n "$s_recheck" ] && q_line=$(awk -v anchor="$s_recheck" '
          NR==anchor { f=1; next }
          f && NF { print; exit }
      ' "$transcript") && printf '%s' "$q_line" | grep -qE '^\[pr/walkthrough\] override-recheck-question: [^[:space:]].*[^[:space:]]$|^\[pr/walkthrough\] override-recheck-question: [^[:space:]]$'
      ```
      (SKILL.md / fixture 内に marker literal の例文が引用されて
      transcript に落ちても、awk trigger を `s_recheck` の実測行番号
      にピン留めすることで最初の一致 (=引用例文) には反応しない。
      `$` anchor で末尾装飾を禁じ、質問文の先頭・末尾が非空白文字で
      あることを担保。1 文字質問文と複数文字質問文の 2 分岐で OR)
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
