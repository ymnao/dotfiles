---
name: pr
description: Create a pull request from the current branch
---

Create a pull request from the current branch based on its commit history and diff.

## Steps

1. Run `bash "$HOME/.claude/skills/pr/scripts/gather-branch-info.sh"` to gather local branch info (git/file only — no GitHub API calls)
2. Check for an existing OPEN PR for this branch (avoids creating a duplicate):
   - `OWNER=$(gh repo view --json owner --jq '.owner.login')`
   - `gh pr list --head <branch_name> --base <base_branch> --state open --json number,url,headRepositoryOwner --jq "[.[] | select(.headRepositoryOwner.login == \"$OWNER\")]"` — filtering by `headRepositoryOwner` excludes same-named branches from forks
   - 0 matches → proceed to step 3
   - ≥1 match → report the PR URL and stop
3. Pre-check:
   - If `commit_count` is 0 → report no commits from base branch and stop
4. Analyze commit history and diff stat to generate PR title and body:
   - **Title**: Under 70 characters, summarizing the changes
   - **Body**: Use the appropriate template (see below)
5. If `has_remote` is false, run `git push -u origin <branch_name>` to push
6. Create PR with `gh pr create`:
   - If `linked_issue` exists, include `Closes #<number>` in the body

## PR template selection

- If `pr_template` is not null → use it as the PR body template, filling in sections based on commit history and diff
- If `pr_template` is null → use the default template below

### Default template (fallback)

```
## Summary
<1-3 bullet points describing the changes>

## Test plan
<Bulleted test steps>

Closes #<issue number> (only if applicable)
```

## Report format

Created PR: <PR URL>

| Item | Detail |
|------|--------|
| Branch | `<branch_name>` → `<base_branch>` |
| Commits | <commit_count> |
| Changed files | <files_changed> files (+<insertions> -<deletions>) |
