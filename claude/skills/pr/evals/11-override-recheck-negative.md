# eval: pr — override-recheck marker の負回帰 (marker を出してはいけない 3 ケース)

SKILL.md `## Telemetry markers` 節の `override-recheck` /
`override-recheck-question` marker は **条件付き** で発火する
(tier=high × pre-walkthrough override × step 5 walkthrough で新 finding
が surface)。本 eval は 3 条件のいずれかが不成立のケースで marker が
**出ない** ことを負回帰として検証する。issue #167 F3 由来。

サブケースごとに独立した Setup (branch) を持つ。共通 Setup は無い。
共通検証式は各サブケースで再掲する:

```bash
! grep -qE '^\[pr/walkthrough\] override-recheck' "$transcript"
```

prefix `override-recheck` にすることで `override-recheck` 本体と
`override-recheck-question` の両方の不在を 1 grep で保証する。この式は
2 marker literal が `override-recheck` prefix を共有していることに
依存する暗黙契約であり、将来 marker 名が独立 prefix (例:
`recheck-question`) へリファクタされたら以下の disjunction 形に
差し替える必要がある (README §[stub-contracts](README.md#stub-contracts)
の literal pin と同時更新すること):

```bash
! grep -qE '^\[pr/walkthrough\] (override-recheck finding=|override-recheck-question:)' "$transcript"
```

## サブケース A: tier=low + override (walkthrough 自体が発火しない)

**目的**: walkthrough が発火しない tier で override を受け取っても
marker を無条件に出す実装を検出する。tier=medium も同じ分岐 (walkthrough
不発火) なので本サブケースに含めない (fixture 差し替えで medium も再現
可能、コスト削減のため skip)。

Setup: [`README.md#eval-setup`](README.md#eval-setup)
(`BRANCH_SUFFIX=neg-a`) を貼ったうえで、共通 snippet 内の以下 **2 行
(commit 前の src/util.js 追加ペア)** のみを次の 2 行に置換する。他行
(`git checkout -b`、`before_head=$(git rev-parse HEAD)`、以降の
stub/mktemp/trap block) は共通 snippet の順序どおり残す。tier=low を
発火させるため src コード変更を docs 変更に差し替える意図:

置換対象 (共通 snippet L214-L215 相当):
```bash
printf 'export const sub = (a, b) => a - b\n' >> src/util.js
git add src/util.js && git commit -m "feat: sub 関数を追加"
```

置換後:
```bash
printf '\n## eval section\n' >> README.md
git add README.md && git commit -m "docs: README に節を追加"
```

gh stub は step 8 の `gh pr create` で呼ばれるため tier=low でも
共通 snippet 通り差し込まれる (「stub 不要」ではない)。

Prompt:
```
/pr を実行して。分類承認時に「step 4 の draft 判定は別 PR で追う。
normal で作って」と override を指示すること。tier=low なので
walkthrough は発火しない想定。この状況で override-recheck marker が
出ないことを検証する。
```

実行:
```bash
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

Pass criteria:
- [ ] tier=low 判定が transcript に出現
- [ ] override-recheck / override-recheck-question marker が一切出現しない:
      ```bash
      ! grep -qE '^\[pr/walkthrough\] override-recheck' "$transcript"
      ```
- [ ] walkthrough が発火していない (tier=low の場合レビュー自体が
      走らない):
      ```bash
      ! grep -qE '^\[pr/review\] stub-loaded' "$transcript" && \
          ! grep -qE '<command-name>/?codex-review</command-name>' "$transcript" && \
          ! grep -qE '"subagent_type"[[:space:]]*:[[:space:]]*"(codex-review|code-reviewer)"' "$transcript"
      ```

## サブケース B: tier=high + pre-walkthrough override + step 5 で新 finding surface **なし**

**目的**: 3 条件のうち「新 finding surface」だけが不成立のケースで
marker が出ないことを検証する。step 4 の F1 は既知の finding で、step
5 walkthrough では追加 finding が surface しない stub を注入する。

Setup: [`README.md#eval-setup`](README.md#eval-setup)
(`BRANCH_SUFFIX=neg-b`)。10-normal-override.md サブケース B と同じく
tier=high 発火のため共通 snippet の後に以下を追加する (F2 は含まない
step 5 stub を選択):

```bash
cat > package.json <<'JSON'
{
  "dependencies": { "example": "1.0.0" },
  "name": "eval-fixture",
  "private": true
}
JSON
git add package.json && git commit -m "chore: package.json を追加"

stub_step4=$DOTFILES_ROOT/claude/skills/pr/evals/fixtures/reviewer-stubs/10-walkthrough-step4.md
stub_step5=$DOTFILES_ROOT/claude/skills/pr/evals/fixtures/reviewer-stubs/11-walkthrough-step5-nofinding.md
```

Prompt:
```
/pr を実行して。reviewer stub 契約 (stage-gated 注入) を適用する。
- step 4 段階では $stub_step4 のみを読み込み、findings をこの内容と
  みなす。読込時に「[pr/review] stub-loaded stub=<path> count=<n>」
  を行頭一字一句で出力する。
- step 5 walkthrough に到達した時点で $stub_step5 を追加で読み込み、
  step 5 段階の追加 finding とみなす (この stub には新 finding が
  含まれない、count=0 を出力する)。step 5 到達より前に $stub_step5 を
  読み込まない。

step 4 完了時点で「step 4 の draft 判定は別 PR で追う。normal で作って」
と pre-walkthrough override を指示すること。step 5 walkthrough で新
finding が surface しない場合、override-recheck marker を出さずに
normal PR 作成へ進むこと (SKILL.md `## Telemetry markers` 節の発火条件
不成立) を検証する。
```

実行:
```bash
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

Pass criteria:
- [ ] tier=high 判定が transcript に出現
- [ ] step 4 stub 読込 marker が `count=1` で出現:
      ```bash
      grep -qE '^\[pr/review\] stub-loaded stub=.*10-walkthrough-step4\.md count=1' "$transcript"
      ```
- [ ] step 5 stub 読込 marker が `count=0` で出現 (新 finding なしを
      明示):
      ```bash
      grep -qE '^\[pr/review\] stub-loaded stub=.*11-walkthrough-step5-nofinding\.md count=0' "$transcript"
      ```
- [ ] override-recheck / override-recheck-question marker が一切
      出現しない:
      ```bash
      ! grep -qE '^\[pr/walkthrough\] override-recheck' "$transcript"
      ```

## サブケース C: tier=high + override が step 5 の**後**に到着 (post-walkthrough)

**目的**: 3 条件のうち「override が step 5 前」だけが不成立のケースで
marker が出ないことを検証する。walkthrough を通常どおり実施し、F2 が
user に surface された**後**で user が override を指示するため、pre
条件を満たさず marker は不要 (finding は既に user に見えているので
再確認は冗長)。

Setup: [`README.md#eval-setup`](README.md#eval-setup)
(`BRANCH_SUFFIX=neg-c`)。10-normal-override.md サブケース B と同じ
fixture 一式流用 (F2 を含む step 5 stub を選択):

```bash
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

Prompt (canary `F2` は Prompt には書かない):
```
/pr を実行して。reviewer stub 契約 (stage-gated 注入) を適用する。
- step 4 段階では $stub_step4 のみを読み込み、findings をこの内容と
  みなす。読込時に「[pr/review] stub-loaded stub=<path> count=<n>」
  を行頭一字一句で出力する。
- step 5 walkthrough に到達した時点で $stub_step5 を追加で読み込み、
  step 5 段階の新 finding とみなす。同 marker (path 値を差し替え)
  を行頭一字一句で出力する。

step 4 完了時点では override を指示しない。step 5 walkthrough を最後
まで受け、新 finding が surface した後の応答として「walkthrough は
承知した。draft 判定を override して normal で作って」と post-walkthrough
override を指示すること。この場合 pre-walkthrough override 条件が
不成立のため override-recheck marker は出ないこと (SKILL.md
`## Telemetry markers` 節の発火条件不成立) を検証する。
```

実行:
```bash
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

Pass criteria (10-B 同様、以下の shell block と後続 criterion は
**同一 shell セッション** で source する前提。runner が per-criterion
に独立 shell で流す場合は preamble を各 checkbox に inline すること):

```bash
s5=$(grep -m1 -nE '^\[pr/review\] stub-loaded stub=.*10-walkthrough-step5\.md' "$transcript" | cut -d: -f1)
```

- [ ] tier=high 判定が transcript に出現
- [ ] step 4 / step 5 stub 読込 marker が両方 `count=1` で出現し、
      step 5 が step 4 より後:
      ```bash
      grep -qE '^\[pr/review\] stub-loaded stub=.*10-walkthrough-step4\.md count=1' "$transcript" && \
          grep -qE '^\[pr/review\] stub-loaded stub=.*10-walkthrough-step5\.md count=1' "$transcript"
      ```
- [ ] **positive guard**: F2 は walkthrough 内で surface している
      (step 5 stub 読込 marker より **後** に、識別子 `F2` **かつ**
      本文 canary `CANARY-STEP5-BODY` が transcript に出現) — marker が
      出ないのが「walkthrough が動かなかったから」という偽陰性を排除
      するため。識別子だけだと `F2` は他 doc / stub で頻出する pattern
      のため誤 hit する余地があり、canary 併用で「本 stub 由来の
      surface」を強く担保する:
      ```bash
      [ -n "$s5" ] && awk -v start="$s5" '
          NR>start && index($0,"F2") {f2=1}
          NR>start && index($0,"CANARY-STEP5-BODY") {c=1}
          END {exit (f2 && c) ? 0 : 1}
      ' "$transcript"
      ```
- [ ] override-recheck / override-recheck-question marker が一切
      出現しない (override が step 5 後に到着したため pre 条件不成立):
      ```bash
      ! grep -qE '^\[pr/walkthrough\] override-recheck' "$transcript"
      ```

## 共通 Pass criteria

- [ ] codex-review / code-reviewer / fable サブエージェント未起動
      (§[reviewer-stub-contract](README.md#reviewer-stub-contract) 参照)

## Cleanup

[`README.md#eval-cleanup`](README.md#eval-cleanup) 参照。
