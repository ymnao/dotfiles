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
   - **medium**: run the codex-review `security` perspective (follow the codex-review skill's detect→verify→apply steps for that one perspective). Also run the project's test suite if one exists.
   - **high**: run all 3 codex-review perspectives AND the project's test suite. Then do the explain-the-diff walkthrough (step 5).
   - If codex is not installed: record "codex-review skipped (codex not installed)" in the evidence section and continue. Do not silently skip.
   - Draft 判定は **PR-level triage** で行う(codex-review の per-finding 分類 `REPORT-ONLY` / `UNRESOLVED` は参考情報として `$HOME/.claude/skills/codex-review/SKILL.md` の定義に従う。pr の draft 判定に自動流用しない):
     - **本 PR で fix すべき finding が残っている**(未対応、または blocker として判断保留): evidence に記録し **draft** で作成
     - **本 PR で fix する必要がない finding のみ**(verbatim/spec 制約で対応不可 / 追跡別 PR に回す / net-neutral で意図的 skip): evidence に記録するのみ。件数の多寡を draft 判定に使わない
5. Explain-the-diff walkthrough (tier=high only):
   - Split the diff into meaningful units. For each unit present: what changed / why / what could break.
   - Wait for the user's confirmation before `gh pr create`. **Default-deny**: 直前の walkthrough に対する user の明示的な承認応答(「進めて」「OK」等)を確認できたときのみ normal で作成。それ以外(非対話 / 曖昧応答 / 無応答 / 過去会話文脈からの推定 / `/pr` 再実行など walkthrough を提示していないタイミングでの入力)はすべて **draft** で作成し、walkthrough を出力する。
6. Generate PR title and body:
   - **Title**: under 70 characters, summarizing the changes
   - **Body**: use the repo's PR template if `pr_template` is not null, otherwise the default template below. ALWAYS append the evidence section (below) at the end of the body.
7. If `has_remote` is false, run `git push -u origin <branch_name>`
8. Create the PR with `gh pr create`. Add `--draft` when step 4 **or** step 5 decided draft (draft-wins). If `linked_issue` exists, include `Closes #<number>` in the body.

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
