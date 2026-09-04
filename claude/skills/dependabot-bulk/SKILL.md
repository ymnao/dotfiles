---
name: dependabot-bulk
description: Consolidate open Dependabot PRs into one integration branch to compress CI runs from N to 1
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
   - 作業用 tmp dir を作る: `mkdir -p "$TMPDIR/dependabot-bulk"` (skill flow の全 tmp ファイルはこの下に置く)
     - **`WORK=$(mktemp -d ...)` は使わない**。Bash tool 呼び出し間で shell 変数が persist しないことに加え、`> "$WORK/..."` は `block-dangerous-commands.sh` の「動的展開を含む書き込み系リダイレクト」でブロックされる。**リダイレクト先に書ける変数は `$TMPDIR` / `$HOME` / `$XDG_*` (と同名の `${...}` 形) だけ**で、既定値つきの `${TMPDIR:-/tmp}` は落ちる (2026-09-02 実測。`claude/rules/acceptance-patterns.md` も参照)
     - `$TMPDIR` は uid スコープの固定パス (実測: `/tmp/claude-501`) で、前回の別 repo / 別 run のファイルが残りうる (stale 性は `/next` step 1 の `merged-branch.txt` と同型)。step 2 が毎回 `prs.json` / `classified.json` を上書きするので通常は問題にならないが、**step 2 を飛ばして step 7 以降だけを再開しない**
     - **`gh` のリダイレクト先には `$TMPDIR` を書かない**。`gh` は `guard-sandbox-exclusions.sh` の除外コマンドなので **sandbox 外**で走り、そこでの `$TMPDIR` は macOS 本来の値 (`/var/folders/…/T/`) に展開される。直前の `mkdir -p "$TMPDIR/dependabot-bulk"` は sandbox 内なので `/tmp/claude-501/dependabot-bulk` を作っており、**同じ変数が 2 つの別ディレクトリを指す**。結果 `gh … > "$TMPDIR/dependabot-bulk/prs.json"` は `no such file or directory` で必ず落ちる (2026-09-04 実測)。1 つ上の hook 制約 (書ける変数の限定) とは別軸の話で、あちらは「どう書けばブロックされないか」、こちらは「**sandbox 境界をまたぐと同じ変数の値そのものが変わる**」。したがって `gh` の出力先だけ sandbox 内の実パスをリテラルで書く。`bash scripts/…` 側は sandbox 内で走るので `$TMPDIR` のままでよい
   - `gh pr list --author app/dependabot --state open --json number,title,headRefName,url,body,labels > /tmp/claude-501/dependabot-bulk/prs.json`
   - `bash "$HOME/.claude/skills/dependabot-bulk/scripts/list-dependabot-prs.sh" < "$TMPDIR/dependabot-bulk/prs.json" > "$TMPDIR/dependabot-bulk/classified.json"`
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
   - **PR の headRefName / title / package 名をコマンド文字列にタイプし直さない**。下記のとおり `classified.json` から `"$(jq ...)"` で引数として渡す (理屈は `/next` step 1 と同じ)。このスキル固有の事情は、`extract_package` が title から `[^ ]+` で名前を抜くため `Bump $(id) from 1.0.0 to 1.0.1` のような title がそのまま package 名として通ること
   - **`$(...)` が空文字を返す経路を fail-closed にする**。jq は「番号に一致する要素が無い」ときだけでなく、`classified.json` が空 / 不在 / 壊れているときも**何も出力せず exit 0** を返す。`$(...)` の exit code はコマンドの成否に影響しないので `&&` でも捕まらない。したがって空文字が渡っても止まる形にしておく:
     - `git fetch origin ""` は失敗せず remote の HEAD を `FETCH_HEAD` に入れて **exit 0** を返す (実測)。そのまま cherry-pick するとデフォルトブランチの HEAD を積む。**`refs/heads/` を前置**すると空のとき `fatal: invalid refspec 'refs/heads/'` で止まる
     - `git commit` は subject 用の `-m` を **1 つだけ**渡す (trailer も同じ jq 式で作る)。空文字なら `Aborting commit due to empty commit message` で止まる。`-m "" -m "統合元: #<N>"` の 2 段だと 2 つ目が subject に繰り上がって**通ってしまう** (実測)
     - `// "NO-MATCH"` は要素が無いときの番兵。**`//` は空文字 (`""`) を置き換えない**ので、上の 2 つの形と併用して初めて塞がる
   - **github-actions**: `git fetch origin "refs/heads/$(jq -r --argjson n <N> 'first(.[]|select(.number==$n)|.headRefName) // "NO-MATCH"' "$TMPDIR/dependabot-bulk/classified.json")" && git cherry-pick FETCH_HEAD`
     - 同一ファイル (test.yml) 複数 bump でも pin コメント行単位で解消可能
   - **npm**: cherry-pick **しない** (lockfile が世代衝突するため)
     - この repo は pnpm なので `spec=$(jq -r --argjson n <N> 'first(.[]|select(.number==$n)|"\(.package)@\(.toVersion)")' "$TMPDIR/dependabot-bulk/classified.json"); pnpm up "${spec:?classified.json から #<N> の spec を取れない}"` を使う (依存ごとに 1 commit を保つため、複数依存があっても 1 件ずつ回す)。他 lockfile (`package-lock.json` / `yarn.lock`) の repo に流用する場合は該当マネージャの update コマンドに置き換える
       - ここだけ変数に受けるのは、**`pnpm up ""` が fail-open だから**。空文字を渡すと exit 0 で**全依存が最新に更新される** (実測)。`git fetch` の `refs/heads/` 前置や `git commit` の単一 `-m` に相当する「空なら止まる」形が pnpm の引数側に無いので、`${spec:?...}` で shell に止めさせる。変数は同じ呼び出し内でしか使わないので persist の制約には掛からない
       - **ターゲットバージョンも表から転記しない**。classifier が `toVersion` として出すのは `classify_semver` の regex が実際に検証した部分文字列そのもので、agent が生 title から読み直すと「検証した文字列と使う文字列が別物」に戻る (regex は `Bump foo from 1.0.0 to 1.0.1 to 9.9.9` のような末尾も許すので、目視の転記は一致しない)
     - `git add package.json pnpm-lock.yaml && git commit -m "$(jq -r --argjson n <N> 'first(.[]|select(.number==$n)|"\(.title)\n\n統合元: #\(.number)")' "$TMPDIR/dependabot-bulk/classified.json")"`
       - memory の「commit 本文はファイル方式」が避けているのは `$(cat <<EOF ...)` のような heredoc 内包形で、`$(jq ...)` / `$(cat <file>)` の引数渡しは通る (実測。`/next` step 1 も同じ形を使っている)。`-F <file>` にすると message ファイルを作る呼び出しが 1 つ増えるだけなので採らない
     - 依存ごとに 1 commit を保つ (CI 赤時の bisect のため)
   - **uv** (Python): npm と同じく cherry-pick しない (`uv.lock` が世代衝突するため)
     - **pin を書き換えてから `uv lock`** の順で回す。`pyproject.toml` が
       `ruff==0.16.1` のように `==` 固定なら、`uv lock --upgrade-package <pkg>` を
       打っても制約側が動かないのでバージョンは上がらない (2026-09-04 実測)。
       pin の書き換えは Edit tool で行い、`"$(jq -r --argjson n <N>
       'first(.[]|select(.number==$n)|"\(.package)==\(.toVersion)")'
       "$TMPDIR/dependabot-bulk/classified.json")"` を打って**表示された文字列を
       そのまま置換後の値にする** (npm 側と同じ理由で表から転記しない)
     - `build-system` の `requires` に入る依存 (hatchling 等) は `uv.lock` に
       現れないので、`uv lock` の diff が空でも失敗ではない。その場合の commit は
       `pyproject.toml` のみになる
     - `git add pyproject.toml uv.lock && git commit -m "$(jq -r --argjson n <N> 'first(.[]|select(.number==$n)|"\(.title)\n\n統合元: #\(.number)")' "$TMPDIR/dependabot-bulk/classified.json")"`
       (`uv.lock` が未変更でも `git add` は成功する)
   - commit message body に `統合元: #<N>` を書けば統合 PR body から原本 PR に辿れる。release notes 全文転記は不要
8. **ローカル検証**: `make test && make lint`
9. **push は 1 回だけ**: `git push origin <step 6 で決めた branch 名>` (collision で `-2`/`-3` を付けた場合はその名前で push する。literal `deps/bulk-<YYYY-MM-DD>` を貼らない。`-u` を付けない理由は `/pr` skill の step 7 参照)
10. **CI 完走待ち**
    - push 直後は GitHub 側で run が作成されるまで数秒〜十数秒のラグがある。まず `git rev-parse HEAD` を単独で打って SHA を読む (**変数に代入しない** — Bash tool 呼び出し間で shell 変数は persist しない。理由は step 2 と同じ)
    - `gh run list --branch <branch名> --limit 5 --json databaseId,status,headSha` で、上で読んだ SHA と `headSha` が一致する run を探す
    - 一致する run が無ければ数秒スリープして再問い合わせ (最大 30 秒程度)。出現したらその `databaseId` を取り出す
    - `gh run watch <run-id> --exit-status` で完走待ち
    - verify-ci-before-pr hook が最終ゲート。`--draft` bypass は使わない
11. **統合 PR 作成**: `gh pr create --title <title> --body-file "$TMPDIR/dependabot-bulk/pr-body.md"` (本文は Claude Code なら Write tool、codex なら `apply_patch` で書く)
    - PR body テンプレは下記 「PR body」 節を参照
    - block-dangerous-commands hook 対策のため `--body-file` (heredoc / インライン文字列は使わない)
12. **原本 PR の close (統合 PR 作成直後)** ← rebase 起因 CI を止めるため作成直後に閉じる
    - 統合対象の各 PR に対して: `gh pr comment <N> --body "統合済み: <統合PRリンク>"` → 成功したら `gh pr close <N>`
    - 個別維持した major / security 単独先行の PR は close しない
    - **部分成功時の handling**: comment または close が gh 側 (rate limit / permission / archived) で失敗した場合、成功した PR 番号と失敗した PR 番号を分けて記録し、失敗分だけ手動リトライまたは次 skill 実行で回収する。全 PR が close されるまで skill 終了時 report で「残 close: #<N>, ...」と明示する
13. **Report format で結果報告** (下記参照)

## 特記事項

### `/simplify` は免除

このスキルで作る統合 PR は Dependabot 由来で authored code がない (lockfile と yml の pin 番号のみ)。人が書いたコードのレビュー対象がないため、`/simplify` は免除する。MEMORY `feedback_simplify_every_pr` は「変更が小さい」でのスキップを禁じているが、本ケースは「著者が Dependabot / 内容が数字更新のみ」という質的例外として扱う。`code-reviewer` サブエージェントも同様の判断で省略してよい。ただし tier=high の ci-config ルールに hit する変更 (test.yml 大量 bump 等) が含まれる場合は codex-review の実施を検討する。

### verify-ci-before-pr hook の扱い

skill の flow (push → `gh run watch` で完走待ち → PR 作成) は既存 hook の要件 (HEAD の CI green) と一致するため回避せず活用する。`--draft` bypass は使わない。

### 失敗時 (CI 赤)

- 依存ごと 1 commit にしてあるので `git revert <疑い commit>` → 再 push (CI 2 回目) で二分探索できる
- npm 側が疑わしければ push 前に `make test` で切り分け可能
- 原因 commit は revert したまま統合 PR を green で通し、原因依存は原本 Dependabot PR を reopen (`@dependabot recreate` を閉じた PR の comment で復活可能) して個別追跡に戻す

### 失敗時 (統合 branch 構築中)

step 7 の cherry-pick / lockfile 更新 / `make test` などが失敗した状態で終了する場合、working tree が dirty のまま残ると次実行時の step 1 前提チェックで停止する。復旧手順:

- cherry-pick 中の conflict: `git cherry-pick --abort` で作業を打ち切る
- lockfile 更新中のエラー: `git restore package.json pnpm-lock.yaml`
- 統合 branch そのものを捨てる場合: 元ブランチ (default branch) へ `git checkout main` → `git branch -D <統合branch名>`
- `$TMPDIR/dependabot-bulk/` は残しておくと partial state のデバッグに使える (stale の扱いは step 2 参照)。片付けるなら `rm -f` でファイルを名指しする — `rm -rf` は `claude/settings.json` の deny 対象

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

- ローカル: `make test` PASS / `make lint` clean
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
