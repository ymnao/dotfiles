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
   hooks 系 / commands・workflows・mcp 等の Claude 設定ファイル群。
   完全な列挙は harness の Filesystem policy が正本、判定原則は memory
   `project_settings_files_sandbox_lock.md`) に触る PR では unlink 制限で
   checkout / pull / reset --hard が失敗する。状況別 workaround:
   - **feature ブランチ checkout 中**:
     `git fetch origin main:main` (non-fast-forward は refspec が自動拒否
     するので安全) → `git diff HEAD main --stat` が空か確認 → 空なら
     `git checkout main`。fetch が拒否された、または diff 非空 (squash
     merge や他コミット混入) なら user Terminal 依頼にフォールバック
     (memory `project_settings_pr_pull_workaround.md`)
   - **既に main checkout 済みで `git pull` が unlink 失敗**:
     この状況は origin/main が locked file を書き換えている場合に発生
     するため、local main の working tree は古い locked file が残った
     まま。安全な自動復旧手順は無いので **user Terminal で `git pull`
     を実行してもらう**フォールバックにする (Claude から
     `git reset --mixed origin/main` を打つと index/HEAD だけ進み
     working tree の locked file が silent に stale 化するため禁止)
3. **ブランチ削除**: merge 済みの作業ブランチを `git branch -d` で削除する
   (`-D` は使わない。-d が拒否されたら未 merge コミットがある異常なので
   報告して停止)
4. **学びの昇格チェック**: このセッションで CLAUDE.md / skill / memory に
   昇格すべき学び (同じ指摘を 2 回受けた・skill の手順が実態とズレていた等)
   がないか振り返り、あれば提案する (勝手に書き換えない)
5. **handoff**: `/handoff` skill を実行して HANDOFF.md を更新する。
   HANDOFF.md に「次セッション持ち越しメモ」等の恒久メモ節がある場合は
   消さずに引き継ぐ
6. **次タスク候補の提示**: HANDOFF.md の残タスクと open issues
   (`gh issue list --state open --limit 10`) から次の候補を優先順で並べて
   **停止する**。次サイクルは user が `/clear` → `/dev` で開始する
   (ai-operations §4「無関係タスク間で /clear」の定石に従い、同一セッション
   での連続実行はしない)

## 注意

- merge は必ず user が行う。このスキルは merge を確認するだけで、
  `gh pr merge` を実行してはならない
- step 1 で merged を確認できるまで後続 step に進まない (pull が
  fast-forward できない・handoff が中途半端になる事故の防止)
