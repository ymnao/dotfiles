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

機械検証可能:
- [ ] `/dev` が新しい feature ブランチを作成した (main のままではない)
- [ ] `tmp/review-cap-target.sh` が commit され、その後 round1 stub の
      指摘 1 件 (未使用変数削除) に対応する fix コミットが 1 本以上入った
- [ ] レビューループが **正確に 2 周** 回った (1 周で終わらず、かつ
      3 周目に入っていない)

transcript 判定 (human runner):
- [ ] 1 周目で round1 stub を読み、記載された 1 件を apply した
- [ ] 修正コミット後、2 周目を round1 から再開した
- [ ] 2 周目で round2 stub を読み、記載された残存指摘 1 件を **apply せず
      記録** した (fixture の「apply しない」指示に従った)
- [ ] round2 stub 読込〜/pr 起動の区間で fix コミット / Edit / Write が
      **一切ない** (REPORT-ONLY 遵守。/pr 起動後の commit は区間外で許容。
      構造化ログ化して機械検証する案は issue #148 finding 7 で追跡中、
      当面は human runner が transcript 上で判別する)
- [ ] cap (2 周上限) で停止し、残 finding を PR 本文 evidence または
      会話ログに明記した (黙って消えていない)
- [ ] step 5 で /pr を呼び、残 finding が /pr の fix-or-issue ポリシー
      (fix コミット or issue 起票) に必ず引き渡された
- [ ] このループ中に `/simplify` や `/code-review` を **実起動していない**
      (stub 契約遵守)
- [ ] このループ中に codex-review を呼んでいない (/pr 側の重複回避)

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
