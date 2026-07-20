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
   `claude/skills/` 配下を含む PR では sandbox の unlink 制限で
   checkout / pull / reset --hard が失敗する。状況別 workaround:
   - **feature ブランチ checkout 中**: `git fetch origin main:main` →
     `git checkout main` の順にする
     (memory `project_settings_pr_pull_workaround.md`)
   - **既に main checkout 済みで `git pull` が unlink 失敗**:
     `git fetch origin` → `git reset --mixed origin/main`。
     merge 後 tree 一致を前提に index/HEAD だけ進める
     (未 push commit があると使えない)
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
