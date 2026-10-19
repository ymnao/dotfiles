---
name: new-project
description: 個人開発を新しく始めるときに、調査 → GitHub repo 作成 → 初期ファイル → main 保護 (ruleset) → ラベル → チェック → 最初の issue 起票までを 1 本の流れで行う。`/new-project check` で「開発を始められる状態か」のチェックだけを再実行する。既存 repo への後付けには使わない
---

新しい repo を、main が保護され、Claude Code の設定と CI と最初の issue が揃った
状態まで持っていく。手順が頭の中にしかないと main の保護を設定し忘れる (issue #440)。

## 前提

- **起動場所**: 新しい repo を置く親ディレクトリ (例: `~/development`) で起動する。
  repo は cwd の下に clone する。`check` 以外で cwd が git の作業ツリーの中なら
  (`git rev-parse --is-inside-work-tree` が成功したら) 止める — 既存 repo への後付けは対象外
- `<repo-dir>` は新しい repo の作業ツリーの**絶対パス** (`pwd` で得た親ディレクトリ + `/<name>`。
  `check` 単独では `git rev-parse --show-toplevel` の値) で、以後はリテラルで埋める。相対パスに
  しないのは、Bash tool の cwd が呼び出しをまたいで残り、途中で `cd` すると指す先がずれるため
- `gh` は 1 回の Bash 呼び出しに 1 コマンドだけ書き、`&&` / `;` / パイプ / コマンド置換 /
  リダイレクトに混ぜない。加工は `--jq`、対象 repo は `--repo <owner>/<name>` をリテラルで渡す。
  `gh` を bash スクリプトの中から呼ばない (Keychain の認証が切れて必ず失敗する。
  ローカル側のチェックを `check-ready.sh` に分けているのはこのため)
- 外に見える操作 (repo 作成・push・ruleset・ラベル・issue 起票) は、**それぞれ直前に**
  打つコマンドを示して user の承認を取る。1 つの承認を次の操作に流用しない
- 一時ファイルは system prompt が示すセッションの scratchpad ディレクトリに置き、
  リテラルのパスで書く (以下 `<scratchpad>`)。中身は Write tool で書く
- skill 内のファイル (`check-ready.sh` `ruleset.json` と他 skill の SKILL.md) は
  `$HOME/.claude/skills/<skill>/...` で参照する。skill の外の dotfiles (`scripts/` `claude/templates/`) は
  `<dotfiles>` で参照する。`<dotfiles>` は `readlink "$HOME/.claude/skills"` の出力から末尾の
  `/claude/skills` を落とした値で、以後はリテラルで埋める。`$HOME/.claude/skills/../../scripts` の形で
  `claude-init.sh` を呼ばない (`claude-init.sh` は自分の場所を `cd` で求める。bash の `cd` は `..` を
  字面で畳んだ先 (`$HOME/scripts`) が存在するとそちらへ着くので、そのディレクトリがある環境でだけ壊れる)

## Steps

引数が `check` なら step 6 だけを行って終わる。

### 1. 調査

`/grill-me` の聞き方で 1 問ずつ、毎回推奨する回答を添えて決める。コードも repo も
まだ無いので、ここで決めないことは後のステップで推測に置き換わる。

- 作るもの・使う人・最初に動かす範囲 (MVP)
- 言語とパッケージマネージャ。`<dotfiles>/claude/templates/` のどれに当たるか
  (当たらなければ step 3 で CLAUDE.md と `.claude/settings.json` を手で書く)
- repo 名 (英小文字・数字・`-` `_` `.` だけ)、public / private (既定は private)、
  public なら LICENSE (推奨は MIT。private では置かない)
- 類似 OSS / サービスを WebSearch で 3 件ほど挙げ、何を真似て何を変えるかを 1 行ずつ

成果は README の下書きと、step 7 の issue 候補の材料にだけ使う。調査レポートの
ファイルは作らない。

### 2. repo 作成

承認を取ってから打つ (`--private` は public を選んだら `--public` に替える。`--license` は
public で LICENSE を付けるときだけ):

`gh repo create <name> --private --gitignore <テンプレート名> --clone`

- `--gitignore` の名前は https://github.com/github/gitignore のファイル名から `.gitignore` を
  落としたもの (例: `Node`, `Python`)
- 出力された URL の `<owner>/<name>` を控える。default branch の名前 (以下 `<branch>`) は
  clone した直後の `git -C <repo-dir> branch --show-current` で控える

### 3. 初期ファイル (main への直接 push はこの 1 回だけ)

1. `bash <dotfiles>/scripts/claude-init.sh --dir <repo-dir> --template <テンプレート名>` で
   CLAUDE.md と `.claude/settings.json` (権限) をコピーし、`.gitignore` に
   `.claude/settings.local.json` を足す。テンプレートが無い言語なら、近いテンプレートの
   2 ファイルに倣って手で書き、`.gitignore` の行も手で足す
2. CLAUDE.md のコマンド表と `.claude/settings.json` の権限を、step 1 で決めた言語・PM の
   実際のコマンドに合わせて直す
3. README を step 1 の下書きで書く
4. `.github/workflows/ci.yml` を 1 本書く。中身は CLAUDE.md のコマンド表にある
   lint / test を実行するだけにする。action の pin は `$HOME/.claude/rules/github-actions.md` を
   Read して従う (repo の外から書くので、path-scoped rule の自動ロードを当てにしない)。
   lint / test のコマンドがまだ無いなら、依存の install が通ることだけを見る job にする
5. オプトイン設定を置くかを聞く。推奨は次のとおり
   - `.claude/stop-gate.conf`: 数秒で終わる lint / test があれば、そのコマンドを 1 行で置く。
     無ければ置かない
   - `.claude/backlog.conf`: 置かない (在庫が問題になってから入れる)
6. `git -C <repo-dir> add -A` → `git -C <repo-dir> commit` (メッセージは `chore: 初期設定`) →
   承認を取ってから `git -C <repo-dir> push origin HEAD`
7. CI の結果を見る: `git -C <repo-dir> rev-parse HEAD` で SHA を取り、
   `gh run list --repo <owner>/<name> --commit <SHA> --limit 1 --json databaseId --jq '.[0].databaseId'`
   で id を取る (`null` なら run がまだ登録されていないので、少し待って打ち直す)。
   `gh run watch <id> --repo <owner>/<name> --exit-status` を単独で打つ。
   落ちたら直すのは step 4 の後 (ブランチ → PR) にして、ここでは main へ再 push しない

### 4. main 保護

承認を取ってから打つ:

`gh api repos/<owner>/<name>/rulesets -X POST --input "$HOME/.claude/skills/new-project/ruleset.json" --jq .id`

- 中身は `ruleset.json` のとおり (default branch の削除・force push の禁止と、PR 経由の
  merge の必須化。承認は 0 件で足りる)。CI の成功を merge 条件にする
  `required_status_checks` は入れない — job 名が決まる前に入れると PR が merge できなくなる
- 失敗したら (プランが private repo の ruleset に対応していない等) エラーをそのまま
  報告して先へ進む。check の main 保護の項目は NG のまま残る

### 5. ラベル

`$HOME/.claude/skills/grill-issue/SKILL.md` の step 9.1 の手順と表 (名前・色・説明) の
とおりに、`need-grill` / `agent-ready` / `agent-wip` / `agent-failed` を作る。表はここに
複製しない (夜間ランナーが読むラベルの正本は grill-issue 側)。

### 6. check

1. `check` 単独で起動したときだけ、repo の中で
   `gh repo view --json nameWithOwner,defaultBranchRef --jq '"\(.nameWithOwner) \(.defaultBranchRef.name)"'`
   を打って `<owner>/<name>` と `<branch>` を取る (通しの流れでは step 2 で控えてある)
2. main 保護: `gh api repos/<owner>/<name>/rules/branches/<branch> --jq '[.[].type] | (["deletion","non_fast_forward","pull_request"] - .) | length'`
   → `0` なら OK。それ以外は足りないルールがある (step 4 をやり直す)
3. ラベル: `gh label list --repo <owner>/<name> --limit 200 --json name --jq '[.[].name] | (["need-grill","agent-ready","agent-wip","agent-failed"] - .) | length'`
   → `0` なら OK。それ以外は step 5 をやり直す
4. ローカル: `bash "$HOME/.claude/skills/new-project/check-ready.sh" <repo-dir>`
   → exit 0 なら OK。NG 行はそのまま報告に載せる

2〜4 の結果を項目ごとに OK / NG で並べて報告し、NG には直し方を添える。step 7 は全件に
`need-grill` を付けるので、3 が NG なら step 5 をやり直してから step 7 へ進む。

### 7. 最初の issue

1. step 1 で決めた内容から issue の候補を作り、title と 1 行の要約の一覧で示して
   承認を取る。件数の上限は設けない
2. 承認された分だけ、write-issue skill の書式で本文を `<scratchpad>/new-project-issue-<k>.md` に
   Write で書き、`gh issue create --repo <owner>/<name> --title "<title>" --body-file <scratchpad>/new-project-issue-<k>.md --label need-grill`
   を 1 件ずつ打つ。`agent-ready` は付けない (着手できるかは後で `/grill-issue` が判定する)

### 8. 報告

repo の URL、check の結果 (項目ごとの OK / NG)、起票した issue の URL を報告する。
