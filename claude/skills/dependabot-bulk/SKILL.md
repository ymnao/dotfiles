---
name: dependabot-bulk
description: Consolidate open Dependabot PRs into one integration branch to compress CI runs from N to 1. Use when several Dependabot PRs are open at once and should be merged together.
---

open な Dependabot PR を 1 branch に統合し、push を 1 回にして CI 実行を N 回 → 原則 1 回に圧縮する。個別 PR ごとに `.github/workflows/test.yml` (push トリガー) が走ることによる GitHub Actions 分数の消費を抑える。

**前提**: `.github/dependabot.yml` に以下 2 点は導入済み。
- `groups: { all: { patterns: ["*"] } }` — ecosystem 内は 1 PR に集約
- `rebase-strategy: disabled` — 他 PR merge 時の自動 rebase (= CI 再走行) 抑制

これにより「PR 1 件 merge するたびに残 Dependabot PR が全部 CI を再消費する」問題は設定側で解消。このスキルは「既に立った PR の後処理 / cross-ecosystem 統合 / groups 未対応 ecosystem 追加時の後方互換」を担う。

## Steps

1. **前提チェック**
   - `git status --porcelain` が空でなければ報告して停止
   - 現在ブランチがデフォルトブランチでなければ、デフォルトブランチに移動する
2. **列挙 + 分類**
   - 作業用 dir を作る: `mkdir -p "<scratchpad>/dependabot-bulk"`。`<scratchpad>` は system prompt が示すセッションの scratchpad ディレクトリで、**リテラルのパスで書く**。skill flow の全一時ファイルはこの下に置き、以下 `<dir>` と書く
     - `$TMPDIR` には置かない。step 7 が `classified.json` を検証済みとして `git fetch` / `pnpm up` に渡すので、dotfiles の `claude/rules/acceptance-patterns.md` の「一時ファイルの置き場」の項に当たる。実例 (issue #502): `$TMPDIR` に置いた `classified.json` が、作業の途中で並走セッションによる別 repo の分類に上書きされた
     - scratchpad を示さない harness (codex 等) では `$TMPDIR/dependabot-bulk-<repo名>` を使う。`<repo名>` は `gh repo view --json name --jq .name` を単独で打って表示された値を書く。この経路は codex で通していない。名前に owner を含まないので、同じ repo や同名の repo (fork と upstream など) を 2 セッションで同時に回すと衝突し、別セッションのファイルも残りうる。step 11 の `--body-file` だけは `$TMPDIR` を展開したリテラルのパスで書く (`verify-ci-before-pr.sh` が変数を含むパスを exit 2 で止める。2026-11-12 実測)
     - **`WORK=$(mktemp -d ...)` は使わない**。Bash tool 呼び出し間で shell 変数が persist しないことに加え、`> "$WORK/..."` は `block-dangerous-commands.sh` の「動的展開を含む書き込み系リダイレクト」でブロックされる。**リダイレクト先に書ける変数は `$TMPDIR` / `$HOME` / `$XDG_*` (と同名の `${...}` 形) だけ**で、既定値つきの `${TMPDIR:-/tmp}` は落ちる (2026-09-02 実測。dotfiles の `claude/rules/acceptance-patterns.md` も参照)
     - 同じセッションで前回回したときのファイルは残りうる。step 2 が毎回 `classified.json` を上書きするので通常は問題にならないが、**step 2 を飛ばして step 7 以降だけを再開しない**
     - **`gh` の行にリダイレクトを付けない**。ファイルへのリダイレクト (`>` / `<`) が付くと除外コマンドの単独行でも sandbox 内で走り、`gh` が TLS 検証で落ちる (Claude Code 2.1.281 で実測。dotfiles の `docs/ai-operations.md` §10「リダイレクト付きの単独行」)。代わりに Bash tool の `run_in_background: true` が書く出力ファイルを経由する
     - 以下の `gh` の手順は Claude Code 向け。codex には `run_in_background` が無く、codex での `gh` の挙動は測っていない
   - `gh pr list --author app/dependabot --state open --json number,title,headRefName,url,body,labels` を **`run_in_background: true` で**起動する (リダイレクトは付けない)。結果の `Output is being written to: <path>` の `<path>` を控える
   - **完了通知で exit code 0 を確認してから**次へ進む。非 0 なら `<path>` を読んで原因を報告して停止する。出力ファイルは stdout と stderr が混ざり、末尾に harness が `[exited with code N]` を追記するので、ファイルの中身で成否を判定しない
   - `jq -n 'input' "<path>" | bash "$HOME/.claude/skills/dependabot-bulk/scripts/list-dependabot-prs.sh" > "<dir>/classified.json"` (`<path>` は控えた実パスを貼る)。`jq -n 'input'` は先頭の JSON 値だけを読むので末尾の追記を無視する。出力ファイルは残る保証が無いので通知を受けたらすぐ取り込み、既に無ければ `gh` の行から打ち直す。jq が parse error で落ちたら (stderr の行が JSON より前に出た等) `<path>` を読んで報告して停止する
   - 出力 JSON の各要素: `{number, title, headRefName, url, package, toVersion, ecosystem, semver, security}`
   - semver は grouped PR (dependabot.yml `groups` 由来の複合 title)・v prefix (`v4.1.1`)・commit-message prefix (`Chore(deps): Bump ...` のような dependabot.yml `commit-message` 由来の接頭辞) を吸収して判定する。判別不能は `unknown`
   - semver / package / toVersion は title のみ、ecosystem は headRefName、security は body と labels から判定する。`-` 始まりの package 名は `pnpm up` にオプションとして解釈されうるので `semver=unknown` に倒れる (個別維持行き)。title は誰でも書ける文字列で、**Dependabot 生成物であることの保証は上の `--author app/dependabot` フィルタが担う**ので、このスクリプトを別経路の PR 一覧に流用しない
3. **表を提示**

   | # | パッケージ | X→Y | semver | ecosystem | ⚠ |
   |---|---|---|---|---|---|
   | ... | ... | ... | patch/minor/major/unknown | github-actions/npm/unknown | 🛡=security |

4. **統合計画を判定 (default rule)**
   - **major** → 個別維持 (統合対象外)。breaking change の判断は人間がやる (release notes の意味的解釈は skill が肩代わりしない)
   - **patch / minor** → 統合対象。ecosystem 横断で 1 PR にまとめる (ecosystem 別分割はしない)
   - **unknown** (grouped PR / pre-release / パース不能) → 安全側で個別維持
   - **security ⚠ (🛡)** → 統合に含めるが表で ⚠ 表示し、user に「単独で先行 merge するか」を明示的に確認する
   - **統合対象が 1 件以下** → 「統合の意味なし。原本 PR をそのまま merge 推奨」と報告して停止
5. **Walkthrough → user 承認待ち** (pr skill step 5 と同型)
   - 統合対象・個別維持・security 単独先行の 3 リストを提示
   - user が `all` 等の明示指示で起動していない限り、次 turn の user 応答を待つ
6. **統合ブランチ作成**
   - base 名 `deps/bulk-$(date +%Y-%m-%d)` を試す
   - 既存の場合 (同日リトライ / 朝夕 2 回運用) は `deps/bulk-<YYYY-MM-DD>-2` `-3` と suffix を付けて空きを探す
   - 決めた名前で `git checkout -b <名前>`
7. **依存ごとに 1 commit を積む** (ecosystem で取り込み方が違う)
   - **PR の headRefName / title / package 名をコマンド文字列にタイプし直さない**。下記のとおり `classified.json` から jq で取り出して渡す (理屈は dotfiles の `claude/rules/acceptance-patterns.md` の「外部由来の名前」の項)。このスキル固有の事情は、`extract_package` が title から `[^ ]+` で名前を抜くため `Bump $(id) from 1.0.0 to 1.0.1` のような title がそのまま package 名として通ること
   - **jq が空文字を返す経路を fail-closed にする**。jq は番号に一致する要素が無いときや `classified.json` が `[]` / 0 バイトのときは**何も出力せず exit 0** を返す。不在や壊れた JSON では非 0 で落ちるが、引数位置の `$(...)` の中ではその exit code が捨てられ、`&&` でも捕まらない。したがって空文字が渡っても止まる形にしておく:
     - `git fetch origin ""` は失敗せず remote の HEAD を `FETCH_HEAD` に入れて **exit 0** を返す (実測)。そのまま cherry-pick するとデフォルトブランチの HEAD を積む。**`refs/heads/` を前置**すると空のとき `fatal: invalid refspec 'refs/heads/'` で止まる
     - commit message は jq 式 1 つで本文全体を書き出して `git commit -F` で渡す (下の「commit」の形)。jq の出力が空ならファイルも空になり、`git commit -F` が `Aborting commit due to empty commit message.` で exit 1 になる。`classified.json` が無いときは jq が exit 2 で落ち、`&&` が commit まで進ませない (いずれも 2026-11-12 実測)。`>` は jq が走る前にファイルを空にするので、前回の message は残らない
     - trailer も jq 文字列の中に入れる。`git commit --trailer ...` や `>>` の追記で外から足すと、jq が空でも commit が通り、trailer 行が subject になる (2026-11-12 実測)
     - fetch 行の `// "NO-MATCH"` は要素が無いときの番兵。**`//` は空文字 (`""`) を置き換えない**ので、`refs/heads/` の前置と併用して初めて塞がる
   - **commit** (npm / uv 共通。`<files>` は各 ecosystem の項に書く): `jq -r --argjson n <N> 'first(.[]|select(.number==$n)|"\(.title)\n\n統合元: #\(.number)")' "<dir>/classified.json" > "<dir>/commit-msg.txt" && git add <files> && git commit -F "<dir>/commit-msg.txt"`
     - attribution の trailer を付けるよう指示されているときは、jq 文字列の `#\(.number)` の後に `\n\n` + その trailer 行をそのまま足す (`<` `>` もそのまま書いてよい)
     - **この 1 行は単独の Bash 呼び出しで打つ** (確認用のコマンドを前に付けない。npm の `spec=$(...); pnpm up ...` の行とも分ける)。この行の `>` が、同じ呼び出しの `$(...)` と組になると `block-dangerous-commands.sh` の「動的展開を含む書き込み系リダイレクト」に止まる (判定の説明は `/next` skill step 1 の「この 2 コマンドは別々の Bash 呼び出しで打つこと」の項)。前置きの形によっても止まる。`grep -c 'exclude-newer' "$HOME/x";` の前置きで止まり、`git diff --stat | awk '{print $1}';` の前置きでは通った (いずれも 2026-11-12 実測)。どの前置きが止まるかは書き分けられていないので、前置きは付けない
     - `-m "$(jq ...)"` で渡さないのは、trailer の `<` `>` が入ると、`grep -n 'exclude-newer' uv.lock;` のような前置きを付けただけで同じ判定に止まるから。`-F` 形はこの前置きでは通る (2026-11-12 実測。実例: issue #502)
     - 依存ごとに 1 commit を保つ (CI 赤時の bisect のため)
   - **github-actions**: `git fetch origin "refs/heads/$(jq -r --argjson n <N> 'first(.[]|select(.number==$n)|.headRefName) // "NO-MATCH"' "<dir>/classified.json")" && git cherry-pick FETCH_HEAD`
     - 同一ファイル (test.yml) 複数 bump でも pin コメント行単位で解消可能
   - **npm**: cherry-pick **しない** (lockfile が世代衝突するため)
     - この repo は pnpm なので `spec=$(jq -r --argjson n <N> 'first(.[]|select(.number==$n)|"\(.package)@\(.toVersion)")' "<dir>/classified.json"); pnpm up "${spec:?classified.json から #<N> の spec を取れない}"` を使う (依存ごとに 1 commit を保つため、複数依存があっても 1 件ずつ回す)。他 lockfile (`package-lock.json` / `yarn.lock`) の repo に流用する場合は該当マネージャの update コマンドに置き換える
       - ここだけ変数に受けるのは、**`pnpm up ""` が fail-open だから**。空文字を渡すと exit 0 で**全依存が最新に更新される** (実測)。`git fetch` の `refs/heads/` 前置や `git commit -F` の空ファイルに相当する「空なら止まる」形が pnpm の引数側に無いので、`${spec:?...}` で shell に止めさせる。変数は同じ呼び出し内でしか使わないので persist の制約には掛からない
       - **ターゲットバージョンも表から転記しない**。classifier が `toVersion` として出すのは `classify_semver` の regex が実際に検証した部分文字列そのもので、agent が生 title から読み直すと「検証した文字列と使う文字列が別物」に戻る (regex は `Bump foo from 1.0.0 to 1.0.1 to 9.9.9` のような末尾も許すので、目視の転記は一致しない)
     - 上の「commit」の形で、`<files>` = `package.json pnpm-lock.yaml`
   - **uv** (Python): npm と同じく cherry-pick しない (`uv.lock` が世代衝突するため)
     - **pin を書き換えてから `uv lock --no-config`** の順で回す。`pyproject.toml` が `ruff==0.16.1` のように `==` 固定なら、`uv lock --upgrade-package <pkg>` を打っても制約側が動かないのでバージョンは上がらない (2026-09-04 実測)。pin の書き換えは Edit tool で行い、`jq -r --argjson n <N> 'first(.[]|select(.number==$n)|"\(.package)==\(.toVersion)")' "<dir>/classified.json"` を打って**表示された文字列をそのまま置換後の値にする** (npm 側と同じ理由で表から転記しない)
       - `--no-config` を付けるのは、この Mac の uv (0.13.5) がユーザー設定 (`uv/uv.toml`) の `exclude-newer = "1 day"` を読むから。素の `uv lock` はそれを `uv.lock` の `[options]` に `exclude-newer-span = "P1D"` として書き込み、その設定を持たない lockfile には `uv run --locked` が「needs to be updated」で落ちる (2026-10-27 実測)。CI にはこの設定が無い。実例: ymnao/artificial-market#354 で `uv lock --no-config` の出力は Dependabot の `uv.lock` と同じ blob だった
     - `build-system` の `requires` に入る依存 (hatchling 等) は `uv.lock` に現れないので、`uv lock --no-config` の diff が空でも失敗ではない。その場合の commit は `pyproject.toml` のみになる
     - 上の「commit」の形で、`<files>` = `pyproject.toml uv.lock`
   - commit message body に `統合元: #<N>` を書けば統合 PR body から原本 PR に辿れる。release notes 全文転記は不要
8. **ローカル検証**: CI の workflow が打っているコマンドを手元で打つ。この repo では `make test && make lint`。Makefile が無い repo は `.github/workflows/*.yml` の `run:` をそのまま打つ (例: uv の repo なら `uv run --no-config --locked ruff check` / `uv run --no-config --locked ruff format --check` / `uv run --no-config --locked python -m unittest discover`)
9. **push は 1 回だけ**: `git push origin <step 6 で決めた branch 名>` (collision で `-2`/`-3` を付けた場合はその名前で push する。literal `deps/bulk-<YYYY-MM-DD>` を貼らない。`-u` を付けない理由は `/pr` skill の step 7 参照)
10. **CI 完走待ち** — 待ち方は CI のトリガーで決まるので、先に `grep -n "^on:" -A3 .github/workflows/*.yml` で確かめる
    - **`on: push` がある repo** (この repo を含む): push 直後は GitHub 側で run が作成されるまで数秒〜十数秒のラグがある。まず `git rev-parse HEAD` を単独で打って SHA を読む (**変数に代入しない** — Bash tool 呼び出し間で shell 変数は persist しない。理由は step 2 と同じ) → `gh run list --branch <branch名> --limit 5 --json databaseId,status,headSha` で、上で読んだ SHA と `headSha` が一致する run を探す → 無ければ step 11 の PR body のうち CI 行以外を書いてから再問い合わせする (CI 行は run の完走後に埋める。Claude Code の Bash tool は foreground の `sleep` をブロックするので待つ間に別の作業を挟む。codex では数秒待ってよい。数回問い合わせても出なければ `gh run list` の結果を添えて user に報告して停止する) → 出現したら `gh run watch <databaseId> --exit-status` で完走待ち
    - **`on: pull_request` のみの repo**: push では run が立たないので step 11 (PR 作成) を先に行い、`gh pr checks <PR番号> --watch --fail-fast` で完走を待つ。evidence に書く run-id は `gh pr checks <PR番号> --json link` の `link` (`.../actions/runs/<run-id>/job/<job-id>`) から読む。verify-ci-before-pr hook は「HEAD に紐づく check が無い」状態をこのケースとして許可する (`claude/hooks/verify-ci-before-pr.sh` の最終 `*)` 分岐) ので PR 作成は止まらない
    - どちらでも verify-ci-before-pr hook が最終ゲート。`--draft` bypass は使わない
11. **統合 PR 作成**: `gh pr create --title <title> --body-file "<dir>/pr-body.md"` (本文は Claude Code なら Write tool、codex なら `apply_patch` で書く)
    - PR body テンプレは下記 「PR body」 節を参照
    - block-dangerous-commands hook 対策のため `--body-file` (heredoc / インライン文字列は使わない)
12. **原本 PR の close (統合 PR 作成直後)** ← rebase 起因 CI を止めるため作成直後に閉じる
    - 統合対象の各 PR に対して: `gh pr comment <N> --body "統合済み: <統合PRリンク>"` → 成功したら `gh pr close <N>`
    - 個別維持した major / security 単独先行の PR は close しない
    - **部分成功時の handling**: comment または close が gh 側 (rate limit / permission / archived) で失敗した場合、成功した PR 番号と失敗した PR 番号を分けて記録し、失敗分だけ手動リトライまたは次 skill 実行で回収する。全 PR が close されるまで skill 終了時 report で「残 close: #<N>, ...」と明示する
13. **Report format で結果報告** (下記参照)

## 特記事項

### `/simplify` は免除

このスキルで作る統合 PR は Dependabot 由来で authored code がない (lockfile と yml の pin 番号のみ)。人が書いたコードのレビュー対象がないため、`/simplify` は免除する。「変更が小さい」は /simplify を省く理由にならないが、本ケースは「著者が Dependabot / 内容が数字更新のみ」という質的例外として扱う。`code-reviewer` サブエージェントも同様の判断で省略してよい。ただし tier=high の ci-config ルールに hit する変更 (test.yml 大量 bump 等) が含まれる場合は codex-review の実施を検討する。

### verify-ci-before-pr hook の扱い

skill の flow (push → `gh run watch` で完走待ち → PR 作成) は既存 hook の要件 (HEAD の CI green) と一致するため回避せず活用する。`on: pull_request` のみの repo で PR 作成が先になる場合も、hook は「HEAD に check 無し」を許可するので同じく回避不要。`--draft` bypass は使わない。

### 失敗時 (CI 赤)

- 依存ごと 1 commit にしてあるので `git revert <疑い commit>` → 再 push (CI 2 回目) で二分探索できる
- npm 側が疑わしければ push 前に `make test` で切り分け可能
- 原因 commit は revert したまま統合 PR を green で通し、原因依存は原本 Dependabot PR を reopen (`@dependabot recreate` を閉じた PR の comment で復活可能) して個別追跡に戻す

### 失敗時 (統合 branch 構築中)

step 7 の cherry-pick / lockfile 更新 / `make test` などが失敗した状態で終了する場合、working tree が dirty のまま残ると次実行時の step 1 前提チェックで停止する。復旧手順:

- cherry-pick 中の conflict: `git cherry-pick --abort` で作業を打ち切る
- lockfile 更新中のエラー: `git restore package.json pnpm-lock.yaml`
- 統合 branch そのものを捨てる場合: 元ブランチ (default branch) へ `git checkout <default branch>` → `git branch -D <統合branch名>`
- `<dir>` は残しておくと partial state のデバッグに使える (stale の扱いは step 2 参照)。片付けるなら `rm -f` でファイルを名指しする — `rm -rf` は `claude/settings.json` の deny 対象

### やらないこと

- 外部 fetch (CHANGELOG crawl / OSV / GHSA API 照会) はしない。Dependabot が body に埋めた情報のみを Read する
- 統合 PR の merge 実行 (user 操作)
- `dependabot.yml` 自体の書き換え
- auto-merge 設定
- `dependabot rebase` の利用 (rebase = 原本 branch への push = CI 消費、目的に逆行)

## PR body

```
## 統合対象

| # | パッケージ | X→Y | semver | ecosystem | ⚠ |
|---|---|---|---|---|---|
| #<N> | <pkg> | <X>→<Y> | minor | github-actions |  |
...

## 個別維持 (統合外)

- #<N> <pkg> <X>→<Y> (major)
- ...

## 検証エビデンス

- ローカル: step 8 で実際に打ったコマンドを列挙する (この repo では `make test` PASS / `make lint` clean)
- CI: <run-id> success (verify-ci-before-pr hook 経由で確認済み)

## 原本 PR

- #<N> → close 済 (comment でリンク付与)
- ...
```

## Report format

### Consolidated Dependabot PRs

**統合 PR**: <URL>

**統合済み** (N 件):
- #<N> <pkg> <X>→<Y> (semver / ecosystem)
- ...

**個別維持** (K 件):
- #<N> <pkg> <X>→<Y> (major / unknown / security 単独先行)

**検証**: `make test` PASS / `make lint` clean / CI <run-id> success
