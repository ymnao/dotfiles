# eval: dev — レビューループは 2 周が上限、残 finding は /pr の fix-or-issue-or-dismiss へ委ねる (reviewer stub 決定化)

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
> 実行中は SKILL.md step 4 の `/simplify` / `code-reviewer` を実起動せず、
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
- [ ] 各 round の 各 phase が **正確に 1 回ずつ、start → stub-loaded → end
      の順** で出現している:
      [`#review-loop-phase-order`](README.md#review-loop-phase-order) awk で検証
- [ ] round=1 が「指摘 1 件 apply → 次周へ」で終わった:
      `grep -qE '^\[dev/review-loop\] round=1 phase=end applied=1 status=continue head=[a-f0-9]+ dirty=[01]$' "$transcript"`
- [ ] round=2 が「cap 到達」で終わった (指摘件数の情報は下記 head/dirty
      検証と重複、ここは status 値のみ):
      `grep -qE '^\[dev/review-loop\] round=2 phase=end applied=0 status=cap-reached head=[a-f0-9]+ dirty=[01]$' "$transcript"`
- [ ] 各周で stub-loaded ログが出て指摘件数が期待どおり:
      `grep -qE '^\[dev/review-loop\] round=1 phase=stub-loaded stub=.*07-round1\.md count=1$' "$transcript"` および
      `grep -qE '^\[dev/review-loop\] round=2 phase=stub-loaded stub=.*07-round2\.md count=1$' "$transcript"`

- [ ] **★主目的**: round=2 で fix / commit / uncommitted change が
      **一切発生していない** (REPORT-ONLY 遵守を機械検証):

      ```bash
      start_head=$(grep -oE '^\[dev/review-loop\] round=2 phase=start head=[a-f0-9]+ dirty=[01]$' "$transcript" | awk '{print $4" "$5}')
      end_head=$(grep -oE '^\[dev/review-loop\] round=2 phase=end applied=0 status=cap-reached head=[a-f0-9]+ dirty=[01]$' "$transcript" | awk '{print $6" "$7}')
      [ -n "$start_head" ] && [ "$start_head" = "$end_head" ]
      ```

      (SKILL.md 構造化ログの `head=<sha>` `dirty=<0|1>` を文字列一致で
      比較。round=2 の start と end で HEAD SHA と dirty 値の両方が
      同一なら、Bash / apply_patch / sed 経由も含めて round=2 中に
      新たな変更が入らなかったことを保証できる。dirty=0 を強制しない
      のは sandbox 制約由来の pre-existing artifact を許容するため
      (SKILL.md の「round=2 の head/dirty 不変」節参照))
- [ ] このループ中に stub 契約対象の reviewer (`/simplify` slash command
      と `code-reviewer` サブエージェント) を **実起動していない**:
      [`review-loop-stub-not-invoked`](README.md#review-loop-stub-not-invoked) の 2 grep で検証

transcript 判定 (human runner):
- [ ] 2 周目で round2 stub の残存指摘 1 件の内容を **記録** した
      (fixture の「apply しない」指示に従い、内容の妥当性を人間が確認)
- [ ] cap (2 周上限) 到達後、残 finding を PR 本文 evidence または
      会話ログに明記した (黙って消えていない)
- [ ] step 5 で /pr を呼び、残 finding が /pr の fix-or-issue-or-dismiss ポリシー
      (fix / issue 起票 / 対応しない の三択) に必ず引き渡された

### cap 到達後 checkpoint 発火 checklist (issue #163 項 6)

/pr に引き渡された残 finding が (b) or (c) を含むため /pr step 4 の
user checkpoint が発火する。以下 3 点を human runner が確認する
(gh 呼び出し履歴の機械検証は pr/evals/07-checkpoint-gate.md 側で担当。
本 eval は「cap 到達 → checkpoint 発火」の橋渡し経路の確認に focus):

- [ ] cap 到達後、/pr の分類表が transcript に提示された (行頭 `|` +
      `Finding` の header 行が cap-reached ログ以降に出現)
- [ ] 分類表提示から user 承認までの間に、`gh issue create` / `gh pr create`
      が実行されていない (cap 引き渡し由来の finding に対する副作用ゼロ):
      Setup で記録した `before_issues` と、承認前時点の
      `gh issue list --state open --limit 100 --json number -q '.[].number' | sort -u`
      が一致すること。PR は `gh pr list --state all` の前後 diff で判定
      ([`README.md#pr-not-created-check`](README.md#pr-not-created-check))
- [ ] user 承認後にのみ issue 起票 / PR 作成が進行した (承認応答を
      入れずに終わった eval 実行では PR も issue も作られていない)

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
