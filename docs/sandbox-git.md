# sandbox 内の git

agent の sandbox 内で git の ref 操作 (init / checkout / merge / fetch / push /
branch -d / worktree) をするときの罠と回避手順。

## エラーを出しながら本体は成功する 2 種類

sandbox 内の git は、次の 2 種類のエラーを出しながら**本体の操作には成功する**。

1. config を書くサブコマンド (`push -u` / `branch -d` 等) は、sandbox が repo の
   `.git/config` を lock できないため `error: could not lock config file .git/config` を出す
2. proxy を通る network 操作 (`push` / `fetch` / `ls-remote` 等) は、`-u` の有無や
   config と関係なく `fatal: failed to store: 100001` を出す。git は通信の成功後に、
   sandbox が注入した proxy URL の資格情報を credential helper に保存しようとする
   (`http.c` の `credential_approve(&proxy_auth)`) が、proxy のホストに当たる system の
   osxkeychain への保存が sandbox 内では失敗するため (2026-09-27 に git 2.55.0 で実測。
   `-c credential.helper=` で helper を空にすると出ない)

`fatal:` を失敗と読んで中断しない。成否はエラー出力ではなく**結果の状態**で確かめる
(push / fetch は `git ls-remote` の remote SHA と手元の SHA の一致、削除は
`git branch` の出力)。push に `-u` を付けないのは、`.git/config` の lock 失敗 (上の 1) で
upstream 設定の書き込みだけが `error: unable to write upstream branch configuration` を出すため。

`git ls-remote --heads` には `refs/heads/` を付けた完全な ref を渡す。短い名前は ref の
末尾一致になり、別ブランチの行を拾う (`git ls-remote --heads origin bump-actions` は
`refs/heads/chore/bump-actions` を返す。`refs/heads/bump-actions` なら返さない)。

## 削除を拒否するパス

sandbox の denyWithinAllow に入っているパス (settings 系・skills 系・hooks 系・
agents / rules など、`~/.claude/` 配下へ symlink する設定資産。完全な列挙は harness の
Filesystem policy が正本) は、Bash 経由では書き込めない (git の unlink を含む。
Edit / Write tool では書ける)。そのため、これらのパスの中身を書き換える checkout /
pull / merge は失敗するか、半端な状態を残す (以下の各節)。

## remote 追跡ブランチから `checkout -b` / `switch -c` で切る: config を書かない 2 段階

「本体は成功する」は全てのコマンドには当てはまらない。
`git checkout -b <branch> origin/<branch>` は upstream 設定の書き込みに失敗すると、
**ref だけ作って HEAD は元のまま・index と working tree だけ切り替え先のツリーに
置き換わる半端な状態を残す** (2026-08-07 に実測。`tests/` が物理的に消えた)。
`git switch -c <new> <start>` も同じ形で止まり、元ブランチ上で「新ブランチに無い
ファイル」がすべて staged な削除 (`D`) に見える (portfolio repo で 2026-08-18 に実測。
`<start>` の種別は記録されていない)。

止まるのは upstream を書くときだけで、git の既定 (`branch.autoSetupMerge=true`) が
upstream を書くのは start-point が remote 追跡ブランチのときに限る (`git help config`)。
start-point なしの `git switch -c <new>` が fatal を出さずに通ることは ghirgana repo で
2026-09-07 に実測している。

remote 追跡ブランチから切るときは `git branch --no-track <branch> origin/<branch>` →
`git checkout <branch>` の 2 段階で行う。半端な状態からの復旧は、新ブランチで続けるなら
`git switch <branch>` (`-c` なし。ref が意図した commit を指していることを先に確かめる)、
元ブランチに戻るなら `git restore --source=HEAD --staged --worktree .`
(`reset --hard` は禁止のまま)。

復旧後も、`claude/skills/` など sandbox が削除を拒否するパスの実体ファイルが
untracked として残り、以後の `git checkout` / `git merge` が「上書きされる untracked
がある」と言って中断することがある。**古い commit のツリーへ checkout する作業自体を
避ける** (新しいブランチを main から切って変更を載せ直す方が速い)。

## `git init` は完走しない (回避策なし)

`git init -b main` は hooks の sample のコピーで `Operation not permitted` になり、
`--template=<空ディレクトリ>` で hooks を避けても `.git/config` を書けずに止まる
(2026-09-25 に実測)。新規 repo は `git init` だけ user に依頼する (fish 構文で提示)。
以降の add / commit / push と `gh repo create --source=<path> --push` は通る。

## 既存ブランチ間の checkout で locked path が `M` で残る

既存ブランチ間の `git checkout <branch>` も、locked path (`agents/AGENTS.md` など
sandbox が書き換えを拒否するパス) の中身が両ブランチで違うと、**HEAD は切り替わるのに
そのファイルだけ前のブランチの内容で `M` として残る** (エラーで止まらない。
2026-09-26 に `agents/AGENTS.md` で踏み、`make gate` の drift 検査で初めて気付いた)。

checkout 直後に `git status --porcelain` を見て、locked path が `M` なら Edit tool で
checkout 先の内容に戻し、`git diff HEAD` が空になったことを確かめる。

## feature ブランチへの `git merge main`

feature ブランチに `git merge main` する形も、同じ「削除を拒否するパス」で中断する。
main 側がそれらを書き換えていると `error: unable to unlink old ...` に続いて
`Merge with strategy ort failed.` で止まる。**失敗自体は安全** (working tree 無傷・
HEAD 不動で、`checkout -b` のような半端な状態は残らない)。

回避は「main 側の変更内容を **file 編集 tool** で working tree に適用 → commit →
再度 merge」(差分が消えれば git はそのファイルを触らない。2026-08-08 実測)。

## worktree で並行作業する代償

別作業のブランチを切り替えずに並行で進めたいときは、scratchpad に
`git worktree add` できる (「削除を拒否するパス」も worktree 側では掛からない)。
ただし代償がある (1・2 は 2026-09-25 実測)。

1. `make test` の `verify-sandbox-codex-enforcement.sh` と html-brief の outside-tmp
   ケースは repo の置き場所に依存して必ず落ちる (前者は `SANDBOX_RUNTIME=0` で skip
   できる。後者は CI で見る)
2. 片付けの `git worktree remove` / `prune` は `.git/worktrees/<名前>` の削除を sandbox に
   拒否され、そのブランチも「worktree で使用中」として消せない。`git worktree prune` と
   `git branch -D` は user の Terminal に依頼する
3. Bash の cwd が本体に戻るので PR は `gh pr create -R … --head <branch>` の形になり、
   verify-ci-before-pr hook が止める (cwd の HEAD の CI しか見られないため。#382)。
   回避は hook の stderr に従う。`--head` には自分で切ったブランチ名だけを渡す
   (理由は `claude/rules/acceptance-patterns.md` の「外部由来の名前」の項)
