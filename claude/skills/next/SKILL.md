---
name: next
description: merge 後の後始末を 1 コマンドで実行する — merged 確認 → main を pull → ブランチ削除 → handoff 更新 → 次タスク候補の提示
---

`/dev` で作った PR を user が merge した後のセッション締め処理。
「merged. main で pull して handoff」という定型指示を 1 コマンドに置き換える。

## Steps

1. **merged 確認**: `gh pr view --json state,mergedAt,url` で現ブランチの
   PR 状態を確認する。merged でなければ (open / closed-unmerged / PR なし)
   状態を報告して**停止する** (pull もブランチ削除もしない)
2. **main 更新**: `git checkout main` → `git pull origin main --ff-only`。
   sandbox denyWithinAllow に含まれるパス (settings 系 / skills 系 /
   hooks 系 / agents・rules・commands・workflows・mcp 等の Claude 設定
   ファイル群 = ~/.claude/ 配下に symlink する設定資産一般。完全な列挙は
   harness の Filesystem policy が正本、判定原則は memory
   `project_settings_files_sandbox_lock.md`) に触る PR では unlink 制限で
   checkout / pull / reset --hard が失敗する。状況別 workaround:
   - **feature ブランチ checkout 中**:
     `git fetch origin main:main` (non-fast-forward は refspec が自動拒否
     するので安全) → `git diff HEAD main --stat` が空か確認 → 空なら
     `git checkout main`。この fetch は `.git/config` の lock 失敗で
     `fatal:` を出しながら ref の更新には成功する (CLAUDE.md「変更時の
     注意」)。**`fatal:` で中断しない** — 拒否されたかどうかは同じ出力の
     `! [rejected]` 行の有無で判定する (`fatal:` だけなら成功)。
     拒否された場合、または diff 非空の場合 (squash merge / 他コミット
     混入) は user Terminal 依頼にフォールバック
     (memory `project_settings_pr_pull_workaround.md`)。**拒否と diff は
     別々に見る** — 拒否されても local main が偶然 HEAD と同一 tree なら
     diff は空になり、stale な main へ checkout してしまう
   - **既に main checkout 済みで `git pull` が unlink 失敗**:
     この状況は origin/main が locked file を書き換えている場合に発生
     するため、local main の working tree は古い locked file が残った
     まま。安全な自動復旧手順は無いので **user Terminal で `git pull`
     を実行してもらう**フォールバックにする (Claude から
     `git reset --mixed origin/main` を打つと index/HEAD だけ進み
     working tree の locked file が silent に stale 化するため禁止)
3. **ブランチ削除**: merge 済みの作業ブランチを `git branch -d` で削除する
   (`-D` は使わない。-d が拒否されたら未 merge コミットがある異常なので
   報告して停止)。これも config lock の警告を出しながら削除には成功する
   ので、`git branch -d <branch>` と `git branch` を **`;` で continue**
   させて 1 コマンドで打ち (`&&` にしない)、**警告文ではなく後者の出力**で
   消えたことを確認する
4. **学びの昇格チェック**: このセッションで CLAUDE.md / skill / memory に
   昇格すべき学び (同じ指摘を 2 回受けた・skill の手順が実態とズレていた等)
   がないか振り返り、あれば提案する (勝手に書き換えない)。
   - **ここで拾うのは merge 後に判明した分**。作業中に判明した昇格は
     `/dev` の step 5a で PR 本体に載せ済みのはず (載っていない = 5a の
     漏れなので、その旨も報告する)
   - **user の承認を得て反映を終えてから step 5 へ進む** (承認待ちのまま
     handoff を書くと HANDOFF.md が「承認待ち」で確定してしまい、直後に
     承認されても記述が stale になる)。repo に置くものは merge 済み main
     から作業ブランチを切って commit し、memory はその場で反映する
   - 反映結果 (どこに何を書いたか / ブランチ名) を step 5 の handoff に
     引き継ぐ
5. **handoff**: `/handoff` skill を実行して HANDOFF.md を更新する。
   HANDOFF.md に「次セッション持ち越しメモ」等の恒久メモ節がある場合は
   消さずに引き継ぐ
6. **次タスク候補の提示**: HANDOFF.md の残タスクと open issues
   (`gh issue list --state open --limit 10`) から次の候補を優先順で並べて
   **停止する**。次サイクルは user が `/clear` → `/dev` で開始する
   (ai-operations §4「無関係タスク間で /clear」の定石に従い、同一セッション
   での連続実行はしない)。あわせて **健康状態**を 3 行で報告する
   (`.claude/backlog.conf` がある repo のみ。無ければ省略):
   - **内向き比率**: 直近 20 件の merged PR のうち、内向き (`claude/`
     `codex/` `tests/` `docs/` `.github/` のみを触るもの) の割合を
     `gh pr list --state merged --limit 20 --json number,files` の実測から
     算出する。`INWARD_RATIO_MAX` を超えていたら、次サイクルの候補は外向きを
     既定にして提示する。**これが本体の指標** — repo の目的側が進んでいるかを
     直接見ている
   - `open <数> / cap <BACKLOG_CAP>` と今サイクルの delta (起票 − close)。
     cap 超過は「起票ゲートが機能していない」サインとして報告するだけで、
     棚卸しの強制はしない
   - **30 日以上更新の無い issue** の一覧 (`gh issue list --state open
     --search "updated:<YYYY-MM-DD" --limit 20`)。**自動 close はしない** —
     close / 統合 / 残す を提案して user に選ばせる。自動 close は大規模 repo で
     摩擦を生むことが知られており (kubernetes/kubernetes#103151)、判断は人が持つ

   なお、**この節の計測自体を作り込まない**。集計スクリプトや eval を足したく
   なったら、それは「改善機械を改善する機械」であり本末転倒のサイン。gh の
   出力を目視で数える以上のことはしない

## 注意

- merge は必ず user が行う。このスキルは merge を確認するだけで、
  `gh pr merge` を実行してはならない
- step 1 で merged を確認できるまで後続 step に進まない (pull が
  fast-forward できない・handoff が中途半端になる事故の防止)
