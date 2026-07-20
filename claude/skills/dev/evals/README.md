# dev skill evals

`/dev` skill(タスク受付 → 実装 → レビューループ → PR 作成)の振る舞いテスト。
共通の実行方法は [`../../codex-review/evals/README.md`](../../codex-review/evals/README.md)
を参照(サンドボックスリポジトリ、3 回実行 3/3 PASS、モデル指定等)。
このファイルは dev/next 固有の共通スニペットを定義する。

## 共通スニペット(全 eval で使う規約)

### transcript 変数 <a id="transcript-var"></a>

Pass criteria で `$transcript` を参照する eval (dev/06, dev/07 等の
review-loop ログ検証) では、runner は `claude --model ... -p "..."` の
標準出力をファイルに保存し、そのパスを `transcript` に束縛して Pass
criteria の各 grep コマンドに渡す:

```bash
set -o pipefail
transcript=$(mktemp)
trap 'rm -f "$transcript"' EXIT INT TERM
claude --model claude-sonnet-5 -p "<Prompt の内容>" | tee "$transcript"
# 以降 Pass criteria: grep ... "$transcript"
```

`pipefail` 未設定だと `claude` が失敗しても `tee` の成功で runner が
続行し途中 transcript を評価してしまう。`trap` は割り込み時の
mktemp ファイル残留を防ぐ (両方セットで初めて安全)。

skill-creator の eval 実行機能を使う場合はそのセッション出力を同等の
ファイルに落として `$transcript` として渡す。

### レビューループの stub 契約遵守 grep <a id="review-loop-stub-not-invoked"></a>

dev/06 / dev/07 のように reviewer stub 契約 ([`reviewer-stub-contract`](#reviewer-stub-contract))
を適用する eval では、`/simplify` `/code-review` `codex-review` を
実起動していないことを以下の共通 grep で検証する (単なる文中言及と
区別するため `<command-name>` タグ形式に限定):

```bash
! grep -qE '^<command-name>(/?simplify|/?code-review|/?codex-review)</command-name>$' "$transcript"
```

### branch 変数

貼付でシェル構文エラーを起こさないため、setup / cleanup で `<...>` bracket
記法を使わず、setup 冒頭でブランチ名を変数に保存する:

```bash
branch="feature/eval-<name>-$(date +%s)"
git checkout -b "$branch"
```

`<name>` は eval ごとの識別子(`issue-arg` / `review-loop-rerun` 等)。
cleanup では `git branch -D "$branch" 2>/dev/null || true` の形で参照する。

### スキルが作ったブランチの cleanup

`/dev` は eval 実行中に自分でタスク用ブランチを作る。setup で `$branch`
を宣言できないケース (dev/01, 02, 03, 05a, 05b, 05c, 08 等) は cleanup
で `git branch --show-current` から取り、main ガードを付けて削除する:

```bash
branch=$(git branch --show-current)
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
```

### stash 独立性

`git stash list` が空である前提を廃し、eval 実行前後の差分で判定する:

```bash
before_stash_n=$(git stash list | wc -l)
# ... eval 実行 ...
after_stash_n=$(git stash list | wc -l)
# Pass criteria: [ "$after_stash_n" = "$before_stash_n" ]
```

### HANDOFF.md 退避 / 復元 <a id="handoff-backup-restore"></a>

HANDOFF.md はグローバル gitignored(memory `project_handoff_gitignored.md`)。
fixture として使う eval では既存を退避してから上書きし、cleanup で戻す。
退避先は既存 `HANDOFF.md.bak` 等との衝突を避けるため `mktemp` を使う:

```bash
handoff_backup=""
if [ -f HANDOFF.md ]; then
    handoff_backup=$(mktemp)
    mv HANDOFF.md "$handoff_backup"
fi
cp claude/skills/next/evals/fixtures/handoff-template.md HANDOFF.md
# ... eval 実行 ...
rm -f HANDOFF.md
[ -n "$handoff_backup" ] && mv "$handoff_backup" HANDOFF.md
```

`$handoff_backup` を無条件 mktemp するパターンは避ける(元 HANDOFF.md が
無かったケースで復元時に空ファイルを HANDOFF.md として置き残す)。

fixture ファイル名は `HANDOFF.md` にしない(force add 事故の前歴あり)。
setup 内 cp でのみ HANDOFF.md 化する。

### HANDOFF.md gitignore を repo-local に強制する <a id="handoff-local-ignore"></a>

HANDOFF.md の gitignored 前提は user のグローバル gitignore に依存している。
CI や別環境ではグローバル gitignore が異なるため、`git check-ignore HANDOFF.md`
が成立しない可能性がある。eval で `git check-ignore` に依存する場合は setup
冒頭で `.git/info/exclude` に HANDOFF.md を追加し、cleanup で復元する:

```bash
exclude_backup=$(mktemp)
cp .git/info/exclude "$exclude_backup"
grep -qxF 'HANDOFF.md' .git/info/exclude || echo 'HANDOFF.md' >> .git/info/exclude
# ... eval 実行 ...
# cleanup:
mv "$exclude_backup" .git/info/exclude
```

`.git/info/exclude` の write が sandbox / CI で失敗する場合はその eval を
SKIP 扱いにする(fail ではない)。eval を途中 kill した場合は
`.git/info/exclude` 末尾に `HANDOFF.md` 行が残るため、手で削除する。

### setup で `git pull` を実行しない <a id="no-git-pull"></a>

sandbox clone は固定 SHA 前提で作成されるため、setup 内で `git pull` を
実行しない(ネットワーク到達性と remote main の可変状態への依存を排除、
オフライン CI での再現性確保)。`git checkout main` で main に移るだけに
留める。

### PR 非作成の検証パターン <a id="pr-not-created-check"></a>

「eval 中に PR を作っていない」ことを検証する eval では、既存 open PR に
影響されずかつ eval 後に close された PR も検出できるよう `--state all`
の PR 番号セットを setup で記録し、eval 後に diff が空であることを assert
する(`--head` filter を使わない):

```bash
before_prs=$(gh pr list --state all --limit 1000 --json number -q '.[].number' | sort -u)
# ... eval 実行 ...
after_prs=$(gh pr list --state all --limit 1000 --json number -q '.[].number' | sort -u)
# Pass criteria: [ "$after_prs" = "$before_prs" ]
```

前提として PR 総数が 1000 を超えると取りこぼす。現 repo 規模では十分。

### reviewer stub 契約(dev/06, dev/07 決定化) <a id="reviewer-stub-contract"></a>

dev/06 と dev/07 のレビューループは、実 reviewer(`/simplify` /
`/code-review`)の出力が非決定なため findings を stub 化する。stub 契約
の中身は以下で、06/07 の Prompt はこの契約を参照するのみ(3 重管理を
避けるため各 eval には差分だけを書く):

- SKILL.md step 4 の `/simplify` と `/code-review` を **実起動しない**
- 代わりに N 周目のレビュー結果として
  `claude/skills/dev/evals/fixtures/reviewer-stubs/<eval>-round<N>.md` を
  読み、その内容を当該 round の指摘一覧とみなす
- fixture 内で `apply` 指定された指摘のみ修正コミット化する。
  `REPORT-ONLY` と明記された指摘は fix コミットを作らず残存扱いとする
- fixture に書かれていない指摘を **創作しない**
- ループ判定(指摘あり → 再周回 / なし → 完了 / 2 周上限)は SKILL.md
  規約どおり続行する
- stub ファイル自身は指摘一覧とループ判定のみを書く(mechanism 説明の
  再掲はここに集約するため各 stub ファイルには置かない)
- stub を読み込んだ時点で、SKILL.md 構造化ログ (step 4) に加えて以下を
  **行頭から一字一句この形式** で応答テキストに出力する
  (Pass criteria の grep 検証用、前後に装飾を付けない):

  ```
  [dev/review-loop] round=N phase=stub-loaded stub=<path> count=<n>
  ```

  `<path>` は読み込んだ stub の相対パス、`<n>` は stub 内の指摘件数
  (`REPORT-ONLY` を含む全件、apply/skip を問わず)

stub 契約遵守は Pass criteria の transcript 判定チェックボックスで
二重検証する(「`/simplify` / `/code-review` を実起動していない」等)。

## fixtures

`fixtures/` に配置し setup 内で cp / cat して使う:

- `fixtures/readme-typos.md` — `teh` / `fooo` を含む README(dev/02, dev/03)
- `fixtures/review-target.sh` — 未使用変数 + 重複関数(dev/06, dev/07)
- `fixtures/reviewer-stubs/06-round{1,2}.md` — dev/06 のレビューループ
  round 別 canned findings(round1 = 2 件 apply、round2 = 0 件完了)
- `fixtures/reviewer-stubs/06b-round1.md` — dev/06b のレビューループ
  canned findings(round1 = 0 件で 1 周 complete、round2 は出現しない)
- `fixtures/reviewer-stubs/07-round{1,2}.md` — dev/07 のレビューループ
  round 別 canned findings(round1 = 1 件 apply、round2 = 1 件残存 REPORT-ONLY)

## eval 一覧

- 01 — issue 番号受付
- 02 — 引数なし(HANDOFF.md 継続 happy path)
- 02b — 引数なし(HANDOFF.md 空 → 停止)
- 02c — 引数なし(HANDOFF.md 曖昧 = TBD のみ → 停止)
- 03 — 自由文タスク
- 04a — dirty worktree で停止
- 04b — non-main で停止
- 05a — plan 承認ゲート(新機能条件)
- 05b — plan 承認ゲート(hooks / security 境界)
- 05c — plan 承認ゲート(3 ファイル超変更)
- 06 — レビューループ 1 周目からの再回(reviewer stub 決定化済み)
- 06b — レビューループ 1 周完了(round=1 で指摘 0、round=2 に入らず終了)
- 07 — レビューループ 2 周上限(reviewer stub 決定化済み)
- 08 — doc-only PR で walkthrough 抑制
