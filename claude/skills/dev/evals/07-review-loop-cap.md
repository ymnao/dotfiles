# eval: dev — レビューループは 2 周が上限、残 finding は /pr の fix-or-issue へ委ねる (reviewer stub 決定化)

## Setup
`review-target.sh` fixture を修正対象の実ファイルとして扱う。findings は
stub 化し、2 周目に必ず「修正不能な残存指摘」が返る構造にすることで
cap 到達 + 残 finding の /pr 引き渡し経路を必ず実行させる。
**Setup ではブランチを作らず main のまま /dev を実行させる**
(setup で checkout すると 04b の non-main 停止条件が先に発火するため)。

`git pull` は使わない (README の
[setup で `git pull` を実行しない](README.md#no-git-pull) 節参照)。

```bash
git checkout main
# eval が /pr を呼び issue を起票する可能性があるため、既存 open issue の
# 番号を記録しておいて cleanup で差分だけ close する
before_issues=$(gh issue list --state open --limit 100 --json number -q '.[].number' | sort -u)
```

## Prompt

> **stub 契約適用**: `claude/skills/dev/evals/README.md` の
> [reviewer stub 契約](README.md#reviewer-stub-contract) に従い、この eval
> 実行中は SKILL.md step 4 の `/simplify` / `/code-review` を実起動せず、
> N 周目の指摘一覧として `fixtures/reviewer-stubs/07-round<N>.md` を読む。
> round2 stub は `REPORT-ONLY` 指摘を含む(fix コミットを作らず残存扱い)。

/dev claude/skills/dev/evals/fixtures/review-target.sh の内容を
tmp/review-cap-target.sh にコピーしてコミットしてから、レビューループを
回して を実行して (/dev がブランチを作ってから実装する)

## Pass criteria (全項目 AND)

機械検証可能 (transcript を `$transcript` として参照):
- [ ] `/dev` が新しい feature ブランチを作成した (main のままではない)
- [ ] `tmp/review-cap-target.sh` が commit され、その後 round1 stub の
      指摘 1 件 (未使用変数削除) に対応する fix コミットが 1 本以上入った
- [ ] レビューループが **正確に 2 周** 回った:
      `grep -c '^\[dev/review-loop\] round=.* phase=start$' "$transcript"` = 2
- [ ] round=1 が「修正入り次周へ」で終わった:
      `grep -qE '^\[dev/review-loop\] round=1 phase=end applied=1 status=continue$' "$transcript"`
- [ ] round=2 が「cap 到達」で終わった:
      `grep -qE '^\[dev/review-loop\] round=2 phase=end applied=0 status=cap-reached$' "$transcript"`
- [ ] 各周で stub-loaded ログが出て指摘件数が期待どおり:
      `grep -qE '^\[dev/review-loop\] round=1 phase=stub-loaded stub=.*07-round1\.md count=1$' "$transcript"` および
      `grep -qE '^\[dev/review-loop\] round=2 phase=stub-loaded stub=.*07-round2\.md count=1$' "$transcript"`
- [ ] **★主目的**: `round=2 phase=start` から `/pr` skill 起動までの区間で
      fix コミット / Edit / Write の痕跡が **一切ない** (REPORT-ONLY 遵守を
      機械検証):

      ```
      awk '/^\[dev\/review-loop\] round=2 phase=start$/{on=1;next} \
           /^<command-name>\/?pr<\/command-name>$/{if(on)exit} \
           on' "$transcript" \
        | grep -qE '(^<invoke name="Edit"|^<invoke name="Write"|^\[git commit\]|^\* commit [0-9a-f])' \
        && exit 1 || true
      ```

      (awk で round=2 開始行〜`/pr` 起動行の区間を抽出し、Edit/Write tool
      call マーカーまたは fix commit ログ行の不在を確認。hit あれば fail)
- [ ] このループ中に `/simplify` `/code-review` `codex-review` を
      **実起動していない** (slash command 起動マーカーの不在):
      `! grep -qE '^<command-name>(/?simplify|/?code-review|/?codex-review)</command-name>$' "$transcript"`

transcript 判定 (human runner):
- [ ] 2 周目で round2 stub の残存指摘 1 件の内容を **記録** した
      (fixture の「apply しない」指示に従い、内容の妥当性を人間が確認)
- [ ] cap (2 周上限) 到達後、残 finding を PR 本文 evidence または
      会話ログに明記した (黙って消えていない)
- [ ] step 5 で /pr を呼び、残 finding が /pr の fix-or-issue ポリシー
      (fix コミット or issue 起票) に必ず引き渡された

## Cleanup
```bash
pr_number=$(gh pr view --json number -q .number 2>/dev/null)
branch=$(git branch --show-current)
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
[ -n "$pr_number" ] && gh pr close "$pr_number" --delete-branch 2>/dev/null || true
# eval 中に起票された issue を差分で close
after_issues=$(gh issue list --state open --limit 100 --json number -q '.[].number' | sort -u)
new_issues=$(comm -13 <(echo "$before_issues") <(echo "$after_issues"))
for n in $new_issues; do
    gh issue close "$n" 2>/dev/null || true
done
```
