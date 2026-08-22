---
name: next
description: merge 後の後始末を 1 コマンドで実行する — merged 確認 → main を pull → ブランチ削除 → handoff 更新 → 次タスク候補の提示
---

`/dev` で作った PR を user が merge した後のセッション締め処理。
「merged. main で pull して handoff」という定型指示を 1 コマンドに置き換える。

## Steps

1. **merged 確認**: `gh pr view --json state,mergedAt,url,headRefOid,mergeCommit`
   で現ブランチの PR 状態を確認する。merged でなければ (open /
   closed-unmerged / PR なし) 状態を報告して**停止する** (pull もブランチ
   削除もしない)
   - `headRefOid` と `mergeCommit` は step 3 のブランチ削除判定で使う。
     merge 後は不変な値なので**ここで 1 回だけ取り、step 3 で `gh` を
     打ち直さない** (`gh` は単独 Bash 呼び出しを強制されるので、呼び直す
     ぶんだけ tool call が増える)
2. **main 更新**: `git checkout main` → `git pull origin main --ff-only`。
   sandbox denyWithinAllow に含まれるパス (settings 系 / skills 系 /
   hooks 系 / agents・rules・commands・workflows・mcp 等の Claude 設定
   ファイル群 = ~/.claude/ 配下に symlink する設定資産一般。完全な列挙は
   harness の Filesystem policy が正本、判定原則は memory
   `project_settings_files_sandbox_lock.md`) に触る PR では unlink 制限で
   checkout / pull / reset --hard が失敗する。状況別 workaround:
   - **feature ブランチ checkout 中**:
     `git fetch origin main:main` (non-fast-forward は refspec が自動拒否
     するので安全) → **`git diff HEAD main --name-only`** で変更ファイルを
     見る (空かどうかと、どのパスかを 1 回で判定できるので `--stat` は
     打たない) → 空、または locked path を含まなければ
     `git checkout main`。この fetch は `.git/config` の lock 失敗で
     `fatal:` を出しながら ref の更新には成功する (CLAUDE.md「変更時の
     注意」)。**`fatal:` で中断しない**。ただし成否をエラー文言で判定
     するのも誤り (通信 / 認証 / remote 不在でも別の文言が出る) なので、
     **`git ls-remote origin refs/heads/main` と `git rev-parse main` の
     SHA が一致すること**を fetch の成功条件にする。
     **この SHA 一致と diff は別々に見る** — 一致しないまま diff が空に
     なることがあり (local main が偶然 HEAD と同一 tree)、その場合は
     stale な main へ checkout してしまう。**SHA 不一致なら即 user
     Terminal 依頼** (main がそもそも想定と違う状態)。
     **user Terminal 依頼にフォールバックするのは diff が locked path を
     含むときだけ** (memory `project_settings_pr_pull_workaround.md`)。
     **diff 非空を条件にしない** — 自分の PR の後に Dependabot PR 等が
     merge されれば diff は必ず非空になり、unlink 制限と無関係な merge の
     たびに user を止めることになる (2026-08-08 実測: PR #294 merge 後の
     diff は #295 の `.github/workflows/test.yml` 1 件だけで、checkout は
     unlink エラー無しに成功した)
   - **既に main checkout 済みで `git pull` が unlink 失敗**:
     この状況は origin/main が locked file を書き換えている場合に発生
     するため、local main の working tree は古い locked file が残った
     まま。**`git reset --mixed origin/main` を盲目的に打つのは禁止**
     (index/HEAD だけ進み、working tree の locked file が silent に
     stale 化する)。ただし locked file が数個なら、**stale 化しない
     ことを先に実測してから ref を進める**手順が使える:
     1. `git diff --name-only <old> <new>` で変更ファイルを出す
        (locked path が数個に収まらないなら user Terminal に依頼する)
     2. 各 locked path の目的内容を `git show <new>:<path>` で取り出し、
        **Write / Edit tool で working tree に反映**する
        (Bash 経路は unlink できないが file 編集 tool は通る)
     3. **`git diff <new>` が空**であることを確認する
        — これが「working tree が stale でない」ことの実測で、
        この確認を飛ばすと上記の禁止手順と同じ事故になる
     4. `git update-ref refs/heads/main <new>` → `git reset` (mixed)
     5. `git status --porcelain` が空になることを確認する
     実測: 2026-08-06 に PR #278 (skills 2 ファイル) の pull でこの手順を
     使い、`git diff` 空 → ref 前進 → clean を確認した
3. **ブランチ削除**: merge 済みの作業ブランチを `git branch -d` で削除する。
   これも config lock の警告を出しながら削除には成功するので、
   `git branch -d <branch>` と `git branch` を **`;` で continue** させて
   1 コマンドで打ち (`&&` にしない)、**警告文ではなく後者の出力**で消えた
   ことを確認する
   - **`-d` が拒否されたら** (squash merge の repo では元コミットが main の
     祖先にならないため毎回こうなる)、`-d` の安全判定を代替する次の 2 点を
     **step 1 で取った値と照合してから** `-D` を使う。どちらか一方でも
     欠けたら `-D` は使わず**報告して停止する** (step 1 を通過している時点で
     PR が MERGED であることは確定しているので、ここでは確認しない):
     1. step 1 の `headRefOid` と `git rev-parse <branch>` の SHA が一致
        すること。**`-D` で実際に失われうるのは push していないローカル
        commit だけ**なので、ここが安全判定の本体
     2. step 1 の `mergeCommit` の oid を `<sha>` として
        `git merge-base --is-ancestor <sha> main` が **exit 0** を返すこと
        (= PR が入った commit が手元の main に届いている)。exit 1 は未到達。
        exit 128 は object 自体が手元に無い状態で、step 2 の main 更新が
        成功確認をすり抜けて失敗していた場合をここで捕まえる
   - **差分の中身で判定しない**。`git diff main <branch>` の追加行を数える形は、
     後続 PR が既存行を *変更* すると、ブランチが完全に merge 済みでも逆向き
     差分に本物の `+` 行 (書き換え前の内容) が立つため誤って停止する
     (非空 diff に必ず含まれる `+++ b/<path>` ヘッダをどう数えるかでも揺れる)。
     step 2 が checkout について「diff 非空を条件にしない」としているのと同じで、
     条件をファイル名から行に移しても後続 merge で停止する性質は消えない。
     上の 2 点は後続 merge に影響されない
   - 上記 2 点を確認できていれば user に都度確認を取らない。squash merge は
     毎サイクル発生するため、確認を挟むと定型質問が毎回入る
   - 実測: 2026-08-17 に ghirgana で 3 回発生 (PR #11 / #12 / #20 の後始末)。
     remote ブランチは deleteBranchOnMerge で merge 時に消えているので、
     残るのはローカルだけ
   - 実測: 2026-08-23 に dotfiles PR #324 で `gh pr view` が
     `state,mergedAt,url,headRefOid,mergeCommit` の 5 値を 1 回で返すことを
     確認した。`git merge-base --is-ancestor` は祖先 exit 0 / 非祖先 exit 1 /
     object 不在 exit 128 (`fatal: Not a valid commit name`)。旧条件の誤停止は
     scratch repo で再現した — main 側で既存 1 行を書き換えると、完全に squash
     merge 済みのブランチに対して `git diff main <branch>` が
     `+<書き換え前の行>` を出す
4. **学びの昇格チェック**: このセッションで CLAUDE.md / skill / memory に
   昇格すべき学び (同じ指摘を 2 回受けた・skill の手順が実態とズレていた等)
   がないか振り返り、あれば提案する (勝手に書き換えない)。
   - **ここで拾うのは merge 後に判明した分**。作業中に事故を踏んでいれば
     その昇格は `/dev` の step 5b で PR 本体に載っているはず。事故が
     なければ 5b は skip されるので、載っていないこと自体は漏れではない
   - **user の承認を得て反映を終えてから step 5 へ進む** (承認待ちのまま
     handoff を書くと HANDOFF.md が「承認待ち」で確定してしまい、直後に
     承認されても記述が stale になる)。repo に置くものは merge 済み main
     から作業ブランチを切って commit し、memory はその場で反映する
   - **repo 側は commit で止めず `/pr` skill で PR 作成まで行う**。
     `/next` の起動をこの PR 作成の明示指示とみなす (memory
     `feedback_pr_creation` の例外)。commit だけで止めると昇格ブランチが
     宙に浮き、次セッションに「PR を作るだけ」の残タスクとして持ち越される。
     handoff にその 1 行を書く手間ごと無駄になる
   - 反映結果 (どこに何を書いたか / ブランチ名 / PR URL) を step 5 の
     handoff に引き継ぐ
5. **handoff**: `/handoff` skill を実行して HANDOFF.md を更新する。
   HANDOFF.md に「次セッション持ち越しメモ」等の恒久メモ節がある場合は
   消さずに引き継ぐ
6. **次タスク候補の提示**: HANDOFF.md の残タスクと open issues
   (`gh issue list --state open --limit 10`) から次の候補を優先順で並べて
   **停止する**。次サイクルは user が `/clear` → `/dev` で開始する
   (ai-operations §4「無関係タスク間で /clear」の定石に従い、同一セッション
   での連続実行はしない)。あわせて **健康状態**を 2 行で報告する
   (`.claude/backlog.conf` がある repo のみ。無ければ省略):
   - `open <数> / cap <BACKLOG_CAP>` と今サイクルの delta (起票 − close)。
     cap 超過は「起票ゲートが機能していない」サインとして報告するだけで、
     棚卸しの強制はしない
   - **30 日以上更新の無い issue** の一覧 (`gh issue list --state open
     --search "updated:<YYYY-MM-DD" --limit 20`)。**自動 close はしない** —
     close / 統合 / 残す を提案して user に選ばせる。自動 close は大規模 repo で
     摩擦を生むことが知られており (kubernetes/kubernetes#103151)、判断は人が持つ

   **目的側 (日常設定の摩擦) の取りこぼしをここで user に聞かない。**
   頻度や閾値を付けた縮小版も置かない (経緯は `.claude/backlog.conf` の
   コメント。同じ目的の機構を 2 世代廃止している)。

   なお、**この節の計測自体を作り込まない**。集計スクリプトや eval を足したく
   なったら、それは「改善機械を改善する機械」であり本末転倒のサイン。gh の
   出力を目視で数える以上のことはしない

## 注意

- merge は必ず user が行う。このスキルは merge を確認するだけで、
  `gh pr merge` を実行してはならない
- step 1 で merged を確認できるまで後続 step に進まない (pull が
  fast-forward できない・handoff が中途半端になる事故の防止)
