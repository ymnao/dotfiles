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

01-05 は実 gh を投げる従来型 eval。06-10 は **gh stub** と
**reviewer stub 契約** を組み合わせた決定化 eval で、以下の共通スニペット
群を使う。

## 共通スニペット (06-10 で使う規約)

### gh stub の PATH 差し込み <a id="gh-stub-path"></a>

06-10 は `fixtures/stubs/gh` を PATH 先頭に差し込み、実 gh を叩かずに
呼び出し履歴だけ記録する。stub は sandbox 制約で `chmod +x` が済んで
いない場合があるため、setup で mktemp した実行可能コピーを作る:

```bash
stub_bin=$(mktemp -d)
cp claude/skills/pr/evals/fixtures/stubs/gh "$stub_bin/gh"
chmod +x "$stub_bin/gh"
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

# pr create に --draft が付いたか
grep -B1 '^argv\[[0-9]*\]=--draft$' "$EVAL_LOG_DIR/gh-calls.log" \
    | grep -q '^cmd=pr create'
```

stub は `--body-file <path>` の内容を `$EVAL_LOG_DIR/bodies/` に
コピーする (skill 側の `rm` より先に走るため後から assert 可能)。
統合 issue の body に個別 finding が列挙されているかは
`grep 'F1:' "$EVAL_LOG_DIR/bodies/"*` の類で確認する。

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

**実起動禁止の検証**: 06-10 の Pass criteria は codex-review / fable
サブエージェントの実起動禁止を以下 grep で二重担保する:

```bash
! grep -qE '<command-name>/?codex-review</command-name>' "$transcript"
! grep -qE '"subagent_type"[[:space:]]*:[[:space:]]*"(codex-review|code-reviewer)"' "$transcript"
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

stub が呼ばれる eval では `gh-calls.log` に `^cmd=pr create` が
出現しないことで検証する (`gh pr list --state all` 前後比較は不要 —
実 gh を叩いていないため)。

### fixture 一覧

`fixtures/stubs/`:
- `gh` — 実 gh を偽装する bash 3.2 互換スクリプト。呼び出し履歴と
  body-file 内容を `$EVAL_LOG_DIR` に記録、`GH_STUB_FAIL` で失敗注入

`fixtures/reviewer-stubs/`:
- `06-a-only.md` — サブケース A: (a) 直結のみ → checkpoint 発火せず
- `06-b-single.md` — サブケース B: (b) 単独起票
- `06-b-consolidated.md` — サブケース C: 同根 3 件 → 統合 issue 1 本
- `06-b-not-consolidated.md` — サブケース D: 同根なし 2 件 → 2 本
- `06-c-vs-b-default.md` — サブケース E: (c) 3 条件外は (b) default
- `07-b-and-c.md` — user checkpoint 発火 (停止 + 副作用ゼロ + 再開)
- `07-a-only.md` — user checkpoint 発火しない対照
- `08-a-remaining.md` — draft 行 1: (a) 残存
- `08-b-issued-plus-c.md` — draft 行 2: (b) 起票済 + (c) → normal
- `08-c-only.md` — draft 行 3: (c) のみ → normal
- `08-b-issue-failed.md` — draft 行 4: (b) 起票失敗 → draft
- `09-consolidated.md` — 統合 issue 経路
- `10-override-a-remaining.md` — normal override 新条件
- `10-walkthrough-new-finding.md` — walkthrough 新 finding 出現時 override 再確認
