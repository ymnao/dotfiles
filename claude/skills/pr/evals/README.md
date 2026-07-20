# pr skill evals

`/pr` skill の振る舞いテスト。共通の実行方法・サンドボックス方針・
モデル指定・3 回実行 3/3 PASS 基準は
[`../../codex-review/evals/README.md`](../../codex-review/evals/README.md)
を参照。本 README は pr 固有の共通スニペットのみを集約する
(dev/evals/README.md と対の構成)。

## eval 一覧

- 01 — 正常系 (feature ブランチから PR 作成)
- 02 — 重複 PR 検出
- 03 — 0 コミットで停止
- 04 — tier=low (docs のみ) はレビューを省略
- 05 — tier=high (依存変更) はフルレビュー + ウォークスルー
- 06 — 分類分岐 (fix-or-issue-or-dismiss の 5 サブケース、reviewer stub 決定化)
- 07 — user checkpoint 制御フロー (停止 + 副作用ゼロ + 再開)
- 08 — draft 判定表駆動 (4 行: (a) 残存 / (b) 起票済 + (c) / (c) only / (b) 起票失敗)
- 09 — 統合 issue 経路 (gh stub、同根複数 → issue 1 件、body 残留検証)
- 10 — normal override 新条件 (defer marker 抑止 + walkthrough 新 finding 再確認)
- 11 — override-recheck marker の負回帰 (marker を出してはいけない 3 ケース)

01-05 は実 gh を投げる従来型 eval。06-10 は **gh stub** と
**reviewer stub 契約** を組み合わせた決定化 eval で、以下の共通スニペット
群を使う。

## 共通スニペット (06-10 で使う規約)

### gh stub の PATH 差し込み <a id="gh-stub-path"></a>

06-10 は `fixtures/stubs/gh` を PATH 先頭に差し込み、実 gh を叩かずに
呼び出し履歴だけ記録する。stub は git 上で mode 755 で登録済みなので、
setup では mktemp した dir に cp するだけで実行可能:

```bash
stub_bin=$(mktemp -d)
cp claude/skills/pr/evals/fixtures/stubs/gh "$stub_bin/gh"
export EVAL_LOG_DIR=$(mktemp -d)
export PATH="$stub_bin:$PATH"
```

**PATH 伝播の重要事項**: `claude -p` セッション内の Bash tool が
親環境の PATH をそのまま継承するかは環境依存。`claude` を起動する
コマンドラインの `env` 経由で PATH を明示すると確実:

```bash
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

**伝播しない場合の fallback**: サンドボックス repo 直下に `./bin/gh` を
置き、eval Prompt 冒頭で「このセッションでは PATH 先頭に `./bin` を
加えてから作業する」と指示する (これは検証対象の checkpoint 動作に
影響しない補助指示であり、pre-approval hack とは性質が異なる)。

### gh 呼び出し履歴の検証 <a id="gh-calls-log"></a>

stub は `$EVAL_LOG_DIR/gh-calls.log` に「呼び出しごとの `cmd=...` 行 +
`argv[N]=...` 行」を追記する。件数や引数の検証はこのファイルに対する
grep で行う:

```bash
# issue create の回数
grep -c '^cmd=issue create' "$EVAL_LOG_DIR/gh-calls.log"

# pr create のブロックに --draft が含まれるか
# (cmd= 行から次の cmd= までを状態管理する必要があるため awk。
# `grep -B1` では --draft の直前 argv 行しか取れず cmd 行に届かない)
awk '/^cmd=pr create/ {f=1; next} /^cmd=/ {f=0}
     f && /^argv\[[0-9]+\]=--draft$/ {found=1}
     END {exit found?0:1}' "$EVAL_LOG_DIR/gh-calls.log"
```

stub は `--body-file <path>` の内容を `$EVAL_LOG_DIR/bodies/` に
0-padded 連番プレフィックス (`0001-<basename>`) 付きでコピーする
(skill 側の `rm` より先に走るため後から assert 可能、lexical sort が
数値順と一致するため `sort -V` などの GNU 拡張不要)。統合 issue の
body に個別 finding が列挙されているかは各 finding の `file:line` を
直接 grep する (label `F1` 等は fixture 内 identifier で、実 body に
持ち越される保証はない)。

### 選択的失敗注入 <a id="gh-stub-fail"></a>

stub は `GH_STUB_FAIL` 環境変数を見て特定サブコマンドを exit 1 させる。
値はカンマ区切りで、`sub` 単独 (`issue`) または `sub sub2` (`issue create`
`pr create`) を渡す。08 の draft 判定行 4 と 09 の失敗系で使う:

```bash
GH_STUB_FAIL='issue create' env PATH="$stub_bin:$PATH" ... claude -p ...
```

### reviewer stub 契約 (pr 版) <a id="reviewer-stub-contract"></a>

dev/evals の [reviewer stub 契約](../../dev/evals/README.md#reviewer-stub-contract)
を pr にも適用する。差分:

- pr は `/simplify` を回さない (dev step 4 の担当)。stub 対象は
  **codex-review perspectives** および **fable フォールバック** の findings
- pr は round が 1 周のみ。stub ファイルは round 番号を持たず 1 ファイル
  で 1 ケース (例: `fixtures/reviewer-stubs/06-b-consolidated.md`)
- pr 側でも stub 契約の hint を transcript に残すため、stub を読み込んだ
  時点で以下を **行頭一字一句** で出力する (Pass criteria の grep 用):

  ```
  [pr/review] stub-loaded stub=<path> count=<n>
  ```

  `<path>` は読み込んだ stub の相対パス、`<n>` は finding 件数。

**stage-gated 注入 (10-B 用)** <a id="stage-gated-injection"></a>:

reviewer stub 契約は既定で「Prompt 提示時に stub 全体を一度だけ読み込む」
semantics だが、10-B のように「step 5 walkthrough で **初めて** surface
する新 finding」を再現する eval では、単一 stub を最初に読ませると
agent が step 4 段階で新 finding も先読みしてしまい経路を検証できない。

そのため 10-B は stub を **step 4 用** (pre-walkthrough) と **step 5 用**
(walkthrough surface) の 2 ファイルに分離し、Prompt 側で

> step 4 段階では `<step4-stub>` のみを読み込み stub-loaded marker を
> 行頭出力する。step 5 walkthrough に到達した時点で `<step5-stub>` を
> 追加で読み込み、同 marker (path 値を差し替えたもの) を行頭出力する。
> step 5 到達より前に step5-stub を読み込んだり、その内容を言及したり
> しない

と明示指示する。Pass criteria 側は 2 つの stub-loaded marker が
両方出現していること、および step 5 stub 読込より前の出力に step 5
stub 内の finding 識別子が現れないこと (negative grep) で二重検証する。

**限界**: stage-gated は agent の自己申告 (step 5 到達を自身で判定して
2 本目を読む) に依存するため、敵対的耐性は 07 の `--resume` 2 段実行
(SDK 側で turn 境界が確立する) より弱い。将来 `--resume` 化できる場合は
そちらへ移行する。checkpoint 停止・再開の検証には従来通り
[approve-and-resume](#approve-and-resume) を使う (使い分け: 検証対象が
「stop → 承認 → resume」の制御フローなら `--resume`、単に「stage を
超えたタイミングでの stub 追加読込」なら本節の指示ベース)。

**実起動禁止の検証**: 06 以降の Pass criteria は codex-review /
code-reviewer / fable サブエージェントの実起動禁止を以下 grep で三重
チェックする (SKILL.md step 4 codex-fallback bullet 由来。方式変更時は
同期。10-11 Prompt に literal を復唱しない — false-fail 誘発。
**text-mode `-p` の transcript には tool_use JSON が原則流れないため
signal は low**、pattern hit しなくても実起動していない保証にはならない。
確度が要る場合は `--output-format stream-json` で再実行し tool_use を
検査する):

```bash
! grep -qE '<command-name>/?codex-review</command-name>' "$transcript"
! grep -qE '"subagent_type"[[:space:]]*:[[:space:]]*"(codex-review|code-reviewer)"' "$transcript"
! grep -qE '"model"[[:space:]]*:[[:space:]]*"fable"' "$transcript"
```

### transcript 変数 <a id="transcript-var"></a>

dev/evals と同じ pattern (詳細は
[dev/evals/README.md#transcript-var](../../dev/evals/README.md#transcript-var)):

```bash
set -o pipefail
transcript=$(mktemp)
trap 'rm -f "$transcript" "$EVAL_LOG_DIR"/*.log 2>/dev/null; rm -rf "$stub_bin" "$EVAL_LOG_DIR"' EXIT INT TERM
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

### user 承認後再開 (2 段実行) <a id="approve-and-resume"></a>

user checkpoint で **停止した後** の再開挙動を検証する eval (07 の一部)
は、非対話 `-p` mode で 2 段実行する:

```bash
# 1 段目: checkpoint で停止することを確認
session_id=$(env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 --output-format json -p "<Prompt>" \
    | tee "$transcript" | jq -r '.session_id')

# 2 段目: 承認を送って再開
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 --resume "$session_id" -p "OK 進めて" \
    | tee -a "$transcript"
```

`--resume` が想定通り動かない環境ではその eval の再開検証パートを
SKIP と記録する (停止検証パートは 1 段目で確立している)。

### サンドボックス repo と初期 setup <a id="sandbox-repo"></a>

01-05 と同じサンドボックス repo (`skill-eval-sandbox`) を使う。
06-10 は gh stub 経由で本物の GitHub には触らないため、
サンドボックスの整合性 (label / issue seed) には依存しない。ただし
`git` は実際に走らせるので clone 内で実行する。

### PR 非作成の検証 <a id="pr-not-created"></a>

stub が呼ばれる eval では `gh-calls.log` に `^cmd=(pr|issue) create` が
出現しないことで検証する (`gh pr list --state all` 前後比較は不要 —
実 gh を叩いていないため):

```bash
# 2 節構造: gh 未呼び出しなら log ファイル自体が未生成なので、
# ファイル無し = 副作用ゼロ (先の [ ! -f ]) として即 pass 扱いにする
[ ! -f "$EVAL_LOG_DIR/gh-calls.log" ] || \
    ! grep -qE '^cmd=(pr|issue) create' "$EVAL_LOG_DIR/gh-calls.log"
```

### 共通 Setup snippet (06-10) <a id="eval-setup"></a>

06-10 の Setup ブロックはこの snippet を貼るだけで足りる (branch 接尾辞
と stub fixture 選択のみ eval ごとに差し替える):

```bash
set -o pipefail
# サンドボックス repo 内で走らせている前提。dotfiles clone の場所は
# git rev-parse で解決 (絶対パス固定を避ける)。DOTFILES_ROOT を明示的に
# export しておけばそちらを優先する
DOTFILES_ROOT="${DOTFILES_ROOT:-$(cd "$(git -C ~/development/important/dotfiles rev-parse --show-toplevel 2>/dev/null || echo "$HOME/development/important/dotfiles")" && pwd)}"
stub_src="$DOTFILES_ROOT/claude/skills/pr/evals/fixtures/stubs/gh"

git checkout main
branch="feature/eval-pr-${BRANCH_SUFFIX:-triage}-$(date +%s)"
git checkout -b "$branch"
printf 'export const sub = (a, b) => a - b\n' >> src/util.js
git add src/util.js && git commit -m "feat: sub 関数を追加"
before_head=$(git rev-parse HEAD)

stub_bin=$(mktemp -d)
cp "$stub_src" "$stub_bin/gh"
export EVAL_LOG_DIR=$(mktemp -d)
export PATH="$stub_bin:$PATH"

transcript=$(mktemp)
trap 'rm -f "$transcript"; rm -rf "$stub_bin" "$EVAL_LOG_DIR"' EXIT INT TERM
```

追加 fixture (tier=high 評価のための `package.json` コミット等) は
snippet の後に足す。tmpdir スナップショット (09 の body 残留検証) 等
eval 固有の trap 拡張は該当 eval 側で `trap` を再定義する。

### 共通 Cleanup snippet <a id="eval-cleanup"></a>

```bash
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
# stub 出力は setup の trap で削除済み
```

### stub 契約 (body-file 命名 / draft 判定 marker) <a id="stub-contracts"></a>

06-10 の一部 Pass criteria は SKILL.md 側の literal 文字列や mktemp
template に依存する。以下を stub 契約として明示 pin し、SKILL.md の
文言変更で silently fail しないようにする (SKILL.md 側変更時はこの
節も同時に更新すること):

- **一時 body-file の basename**: issue body は `pr-issue-body-*` の
  mktemp template を使う (SKILL.md step 4 に `(例: $TMPDIR/pr-issue-body-<n>.md)`
  として明示。実装は example に従う)。09-consolidated-issue と
  10-normal-override の body-file 残留検証はこの命名に依存
- **draft 判定 marker (SKILL.md step 4 の Draft 判定 bullet 群 + step 5/8)**:
  - **`step 4`** — (a) 未 fix が残っている場合 (bullet 1)
  - **`step 4 pending`** — (b) 起票失敗による draft 退避 (bullet 2 失敗経路)
  - **`step 4 dismiss`** — (c) 対応しない を含む normal (bullet 3)
  - **`step 5`** — tier=high walkthrough で draft 決定 (本 PR eval 未整備)
  - **`step 8 override`** — user 指示による draft override
  08-draft-matrix / 10-normal-override はこれら literal のいずれか適切な
  ものを grep する (行 1 は `step 4`、行 4 は `step 4 pending` 等)
- **walkthrough override-recheck / override-recheck-question marker (SKILL.md
  `## Telemetry markers` 節)**:
  tier=high で pre-walkthrough override を受け取った状態で step 5
  walkthrough が新 finding を surface した際、agent は再確認質問の
  **直前** に以下 2 行を行頭一字一句で出力する:

  ```
  [pr/walkthrough] override-recheck finding=<id>
  [pr/walkthrough] override-recheck-question: <質問文>
  ```

  `<id>` は再確認対象の新 finding 識別子 (stub fixture 内の `F2` 等)。
  10-normal-override サブケース B はこの 2 marker を、`override-recheck`
  行の直後の最初の non-blank 行が `override-recheck-question:` プレフィクス
  で始まり質問文が非空であることまで含めて grep する (marker を出す
  だけで質問せず停止する実装を検出するため)。両 marker は `[pr/review]`
  系 (`stub-loaded`) とは別 namespace で、出所は SKILL.md
  `## Telemetry markers` 節であることに注意

- **classify-risk tier literal (`scripts/classify-risk.sh` 出力)**:
  `classify-risk.sh` は末尾で `jq -n` により pretty-print された複数行
  JSON を出力し、`"tier"` 行は単独行 `  "tier": "<tier>",` として
  transcript に流れる (SKILL.md step 4 の verbatim 転記契約により agent
  応答本文へ)。tier 判定の検証はこの literal を pinned grep で行単位
  hit させる (`<TIER>` は low / high / medium いずれか):

  ```bash
  grep -qE '"tier"[[:space:]]*:[[:space:]]*"<TIER>"' "$transcript"
  ```

  11-A/B/C/D はこの pin を参照する。`classify-risk.sh` の JSON 出力形式
  (キー名 `tier` / 値の quote 形式) を変えたらこの pin を同時更新する。

- **step 5 stub 本文 canary (`10-walkthrough-step5.md` 専用)**:
  `10-walkthrough-step5.md` の F2 定義行に、識別子 `F2` と独立した
  canary token `CANARY-STEP5-BODY` を埋め込む。この token は step 5
  stub 本文と、本 README、および該当 eval の pass criteria (検査式
  の literal 引数) 以外の場所で「agent が読み込む対象として」書いて
  はならない (negative grep の前提)。pass criteria 内の記述は
  transcript には流れないため grep 対象外で、除外して構わない。
  10-normal-override サブケース B の negative grep は step 5 stub
  読込 marker より前に F2 識別子と canary の両方が出現しないことを
  検証し、識別子だけ伏せて本文を先読み言及する実装を捕捉する
  (canary は「事前先読み検出」用途で、事後 surface の positive
  guard 用途では paraphrase 耐性がないため使わない)
