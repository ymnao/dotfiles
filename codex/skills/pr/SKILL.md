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
   - Run `bash "$HOME/.codex/skills/pr/scripts/gather-branch-info.sh" <default-branch>` substituting the value literally
2. Check for an existing OPEN PR for this branch (avoids creating a duplicate):
   - Run `gh repo view --json owner --jq '.owner.login'` — yields `<owner>`
   - Run `gh pr list --head <branch_name> --base <base_branch> --state open --json number,url,headRepositoryOwner --jq '[.[] | select(.headRepositoryOwner.login == "<owner>")]'`
   - 0 matches → proceed / ≥1 match → report the PR URL and stop
3. Pre-check: if `commit_count` is 0 → report no commits from base branch and stop
4. Classify risk and run tier-appropriate review (do NOT skip this step):
   - Run `bash "$HOME/.codex/skills/pr/scripts/classify-risk.sh" <base_branch>` — yields `{"tier": ..., "reasons": [...]}`
   - **low**: if the project defines lint / typecheck commands, run them and fix failures. No review needed.
   - **medium**: run the project's test suite if one exists. Independent AI review is
     NOT available in this harness (codex reviewing its own diff is self-review, which
     defeats the purpose — the codex-review skill exists only on the Claude Code side).
     Record "independent review skipped (codex harness — run /codex-review from
     Claude Code before merge)" in the evidence section.
   - **high**: same as medium, plus the explain-the-diff walkthrough (step 5) and
     create the PR as **draft**. Recommend in the PR report that the user run the
     Claude-side review (code-reviewer subagent or /codex-review) before merging.
   - If review leaves UNRESOLVED findings: do not abort — record them in the evidence section and create the PR as **draft**.
5. Explain-the-diff walkthrough (tier=high only):
   - Split the diff into meaningful units. For each unit present: what changed / why / what could break.
   - Wait for the user's confirmation before `gh pr create`. If running non-interactively, output the walkthrough and create the PR as **draft**.
6. Generate PR title and body:
   - **Title**: under 70 characters, summarizing the changes
   - **Body**: use the repo's PR template if `pr_template` is not null, otherwise the default template below. ALWAYS append the evidence section (below) at the end of the body.
7. Run `git push -u origin <branch_name>` (no-op if origin is already up to date; also syncs review-fix commits made after an early push). If the push is rejected as non-fast-forward (origin advanced independently), do NOT force push — report the divergence to the user and stop
8. Create the PR with `gh pr create` (add `--draft` when step 4/5 decided draft). If `linked_issue` exists, include `Closes #<number>` in the body.

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
| レビュー | independent review | <skipped (codex harness — run /codex-review from Claude Code before merge) / tier=low のため未実施> |

## レビュー指摘と対応
<この harness では独立レビュー不可。tier=medium/high の場合は「merge 前に Claude Code 側で /codex-review または code-reviewer サブエージェントを実行すること」と明記>

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
