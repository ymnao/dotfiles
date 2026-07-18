---
name: pr
description: Create a pull request from the current branch, with risk-tiered review and a verification-evidence section
---

Create a pull request from the current branch based on its commit history and diff. Before creating the PR, classify the diff's risk tier and run the review depth that tier requires. The PR body must include a verification-evidence section.

## Steps

Run each `gh` command as a bare invocation and substitute prior output literally into the next call (no `VAR=$(...)` wrapping — the permission allow-list matches by command prefix and command-substitution forms break that match).

1. Resolve the default branch and gather local branch info:
   - Run `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'` — yields the default branch (e.g. `main`)
   - If that fails (no GitHub remote), use the empty string; the script falls back to `refs/remotes/origin/HEAD`
   - Run `bash "$HOME/.claude/skills/pr/scripts/gather-branch-info.sh" <default-branch>` substituting the value literally
2. Check for an existing OPEN PR for this branch (avoids creating a duplicate):
   - Run `gh repo view --json owner --jq '.owner.login'` — yields `<owner>`
   - Run `gh pr list --head <branch_name> --base <base_branch> --state open --json number,url,headRepositoryOwner --jq '[.[] | select(.headRepositoryOwner.login == "<owner>")]'`
   - 0 matches → proceed / ≥1 match → report the PR URL and stop
3. Pre-check: if `commit_count` is 0 → report no commits from base branch and stop
4. Classify risk and run tier-appropriate review (do NOT skip this step):
   - Run `bash "$HOME/.claude/skills/pr/scripts/classify-risk.sh" <base_branch>` — yields `{"tier": ..., "reasons": [...]}`
   - **low**: if the project defines lint / typecheck commands, run them and fix failures. No review needed.
   - **medium**: run the codex-review `security` perspective (follow the codex-review skill's detect→verify→apply→confirm steps for that one perspective). Also run the project's test suite if one exists.
   - **high**: run all 3 codex-review perspectives AND the project's test suite. Then do the explain-the-diff walkthrough (step 5).
   - **codex 不能時のフォールバック**(not installed / sandbox skip (exit 3) / rate-limit skip (exit 4) いずれも): 第二意見をゼロにせず、**別系統サブエージェント(Agent tool, `model: "fable"`)のフレッシュレビュー**で代替する。skip された観点のプロンプト(`codex/review-prompts/<P>.md`)と diff を渡し、findings は codex-review と同じ verify→apply 手順で処理する。evidence には「codex-review skipped (<理由>) → fable 代替: <結果>」と記録する。Do not silently skip.
   - **Fix-or-issue ポリシー**: レビューで確認された finding の行き先は「本 PR で fix」か「issue 起票して追跡」の 2 つだけ。「起票せず次セッションに持ち越す」状態を作らない(verify-ci-before-pr hook も body 内の `defer(未起票)` を検出すると `gh pr create` をブロックする)
   - Draft 判定は **PR-level triage** で行う(codex-review の per-finding 分類 `REPORT-ONLY` / `UNRESOLVED` を pr の draft 判定に自動流用しない。用語の定義は `$HOME/.claude/skills/codex-review/SKILL.md` を参照)。**上から順に評価し、最初に一致した bullet を採用**する。bullet 内の処理で state が変わった場合(起票成功で URL が付いた等)は変更後の state で bullet 1 から**再評価する**。いずれの判定でも根拠と該当 finding を evidence に記録する:
     - **本 PR で fix すべき finding が残っている**(未対応、または blocker として判断保留): **draft** で作成
     - **追跡別 PR に回す finding があり、追跡 issue/PR URL が未起票**: **user 確認なしで自動起票する**。finding ごとに一時ファイル(例: `$TMPDIR/pr-issue-body-<n>.md`)へ body を書き出し、`gh issue create --title "<title>" --body-file <path>` で起票する。**title は finding 原文の verbatim 転記ではなく agent が書き直した平文要約**とし、`"` / `` ` `` / `$` / `\` / `$()` を含めない(finding 原文由来の記号がシェル文字列に展開されると command injection になるため。原文の failure_scenario 等は body-file 側にのみ書く — body-file 経由は shell 展開を通らない)。body には `finding の failure_scenario と該当 file:line 抜粋、リンク元 PR/branch` を含める。成功分の URL を evidence 追跡先に記載 → bullet 1 から再評価(全件 URL 付きになれば bullet 3 到達で normal)。失敗時(auth / perms / archived / repo 未指定 等)は **draft** に退避し 根拠 `step 4 pending`(起票失敗、user 対応待ち)を記録。user が事前に「起票しない」等の明示指示を出している場合は起票せず **draft** で作成し、根拠 `step 4 defer` + 指示内容の要約を記録する(追跡先の URL 欄は `defer(未起票)` と書く — draft は hook の defer 検査を bypass するため作成できる。normal に昇格する際に起票が必要)
     - **上記に該当しない**(fix 不要のみ / 追跡 URL 記載済 / 残件なし): **normal** で作成。件数の多寡を draft 判定に使わない。追跡 URL がある場合は evidence に必ず記載する
5. Explain-the-diff walkthrough (tier=high only):
   - Split the diff into meaningful units. For each unit present: what changed / why / what could break.
   - Wait for the user's response. 3 分岐で処理する:
     - (a) **明示的承認**(「進めて」「OK」等、直前の walkthrough を受けた応答): normal で作成
     - (b) **明示的却下 / 修正要求**: `gh pr create` せず中止し、user と対話
     - (c) **曖昧応答 / 無応答**(「うーん」「そうか」等、interactive で直前の walkthrough を受けたが明確でない): PR を作成せず、user に明示的な yes/no を **聞き返す**
   - **walkthrough 未提示のタイミングでの入力**(非対話 / no-tty / `/pr` 再実行など、この turn で walkthrough を提示していない): walkthrough を先に出力し、その turn では **`gh pr create` を実行しない**(次 turn の user 応答を上記 3 分岐で処理する)。
6. Generate PR title and body:
   - **Title**: under 70 characters, summarizing the changes
   - **Body**: use the repo's PR template if `pr_template` is not null, otherwise the default template below. ALWAYS append the evidence section (below) at the end of the body.
7. If `has_remote` is false, run `git push -u origin <branch_name>`
8. Create the PR with `gh pr create`. Add `--draft` when step 4 **or** step 5 decided draft (draft-wins). **Exception**: user が PR 作成前の任意の時点(step 5 の walkthrough 応答 / それ以前 いずれも可、tier を問わない)で「step 4 の draft 判定は別 PR で追う。normal で作って」等、draft 判定を明示的に override する指示を出した場合は normal で作成し、その override 内容(受け取った user 指示の要約と受け取った step)を evidence の Draft 判定に記録する。**制約**: normal override でも hook の defer 検査は bypass されないため、未起票 finding が残ったまま normal 化するには起票が前提。user が起票も拒否して normal を求めた場合は、追跡先の URL 欄に `defer(未起票)` ではなく「追跡しない(user 指示: <要約>)」と記録して作成する(marker 文字列を残すと hook が block して deadlock になる)。ただし **tier=high で override が step 5 前に受け取られた場合**、step 5 walkthrough で新 finding が surface した際は override 継続意思を user に再確認する(walkthrough で見えた新事実に対して pre-walkthrough override が sticky にならないよう safety net)。If `linked_issue` exists, include `Closes #<number>` in the body.

## Default template (fallback)

```
## Summary
<1-3 bullet points describing the changes>

## Test plan
<Bulleted test steps>

Closes #<issue number> (only if applicable)
```

## Evidence section (append to EVERY PR body)

```
<details>
<summary>検証エビデンス</summary>

## リスク分類
tier: <tier> — <reasons を列挙>

## 実行した検証
| 種別 | コマンド | 結果 |
|---|---|---|
| テスト | `<実行したコマンド>` | <PASS/FAIL と件数> |
| Lint | `<実行したコマンド>` | <結果> |
| レビュー | codex-review <観点> | <PASS / N findings (M fixed, K report-only)> |

## レビュー指摘と対応
<codex-review の Report format 表を転記。レビュー未実施なら「tier=low のため未実施」>

## 追跡先
<本 PR で fix せず issue に回した finding を列挙。0 件なら「なし」とだけ書き、表は省略。Finding 列は `file:line — 短い summary(30 字以内)` の compound identifier で書く(codex-review Report format 表には file:line 列が無く、参照だけでは同定不能なため、短い summary を併記して人間可読性を確保)。URL 列は起票済み issue URL を書く(fix-or-issue ポリシーにより normal PR での「未起票のまま列挙」は不可 — hook が `defer(未起票)` を検出すると PR 作成をブロックする。例外は user 明示指示による draft のみで、その場合 `defer(未起票)` と書く)>

| Finding (file:line — summary) | Issue URL |
|---|---|
| <file:line — short summary> | <issue URL または `defer(未起票)`(draft 限定)> |

## Draft 判定
- 判定: <normal / draft>
- 根拠: <step 4 / step 4 pending / step 4 defer / step 5 / step 8 override> — <理由と該当 finding>
- override 内容: <根拠が `step 8 override` のときのみ記載、user 指示の要約と override を受けた step>

</details>
```

Evidence rules (strict):
- Write ONLY results of commands actually executed in this session. Before writing each row, check it against the actual tool output. If a verification was not run, write "未実施" — never leave it blank or omit the row.
- Transcribe outputs as summaries (counts, last lines), not full logs.

## Report format

Created PR: <PR URL>

| Item | Detail |
|------|--------|
| Branch | `<branch_name>` → `<base_branch>` |
| Commits | <commit_count> |
| Changed files | <files_changed> files (+<insertions> -<deletions>) |
| Risk tier | <tier> |
| Review | <PASS / findings summary / skipped reason> |
| Draft 判定 | <normal / draft> — <step 4 / step 4 pending / step 4 defer / step 5 / step 8 override, 理由> |
