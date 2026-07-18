---
name: codex-review
description: Run codex CLI as a second-opinion reviewer of the current diff vs the repo's default branch. Three perspectives (shell-senior / security / qa-fixture); findings are verified against the actual code before any fix is applied.
---

Use the `codex` CLI (independent LLM family) for a second-opinion review of the current branch's diff against the base branch (auto-detected from `origin/HEAD`, default `main`). For each perspective: detect → verify each finding against the real code → apply only confirmed findings that meet the threshold → re-run once to confirm.

## Pre-conditions

Check ALL of these before running. If any fails, report the stated message and stop:

1. The caller's current working directory must be inside the git worktree you want reviewed (or set `CODEX_REVIEW_REPO`).
2. `command -v codex` must succeed. If not → report "codex not installed".
3. `git rev-list --count <base>..HEAD` must be > 0 (base auto-detected; override via `CODEX_REVIEW_BASE`). If 0 → report "no commits beyond <base> to review". Uncommitted-only diffs are out of scope; commit first.

## Perspectives

| Name | Focus |
|------|-------|
| `shell-senior` | bash/POSIX, quoting, `set -euo pipefail` discipline, BSD↔GNU portability |
| `security` | secret leaks, command injection, permissions, input validation |
| `qa-fixture` | test coverage, fixtures, edge cases, determinism |

Default: run all 3 in the order above. If the user named one (`/codex-review security`), run only that.

## Steps (per perspective `<P>`)

### 1. Detect

Run `bash "$HOME/.claude/skills/codex-review/scripts/run-review.sh" <P>` and branch on the exit code:

- `0` (pass) → record perspective as PASS. Go to the next perspective.
- `2` (findings) → stdout is validated JSON. Parse `findings` and go to step 2.
- `1` (setup/parse error) → report the stderr message, record perspective as ERROR, and continue with the next perspective. If 2 consecutive perspectives end in exit 1, stop the whole skill and report to the user.
- `3` (sandbox skip) → record perspective as SKIPPED and continue with the next perspective. If ALL perspectives end in SKIP, stop and point to "Running under a shell sandbox" in Notes for unblock steps.
- `4` (rate-limit skip) → record perspective as SKIPPED (rate limit) and **stop the whole skill immediately** (残り観点も同じアカウントの同じリミット窓に当たるため実行しない)。ERROR カウントには入れない。呼び側 (pr / dev skill) には第二意見のフォールバック (Fable 系統サブエージェントのフレッシュレビュー) を促す。リミット窓は 5 時間/週次単位なのでセッション内リトライはしない。

### 2. Verify (do this for EVERY finding BEFORE applying any fix)

For each finding, Read the actual `file`:`line` (and enough surrounding code to judge). Try to REFUTE the finding:

- The issue does not exist in the current code, is already handled elsewhere, or misreads the diff → verdict **REFUTED**. Record a one-line reason. Do not fix.
- The issue is real → verdict **CONFIRMED**.

### 3. Apply (use exactly these thresholds)

- CONFIRMED and (`severity` == "HIGH" or `confidence` >= 70) → fix in the working tree.
- CONFIRMED but below threshold → do NOT fix; record as REPORT-ONLY.
- REFUTED → do NOT fix.

Do not commit anything — leave fixes in the working tree for the user / `/pr`.

### 4. Confirm (only if fixes were applied)

Re-run step 1 for the SAME perspective exactly once. If it still returns findings, do NOT fix again — record the remaining findings as UNRESOLVED and move on. Max runs per perspective: 2 (one detect + one confirm).

## Report format

End with this table:

| Perspective | Verdict | Findings | Confirmed | Refuted | Fixed | Report-only | Unresolved |
|-------------|---------|----------|-----------|---------|-------|-------------|------------|
| shell-senior | PASS | 0 | - | - | - | - | - |
| security | FIXED | 3 | 2 | 1 | 2 | 0 | 0 |
| qa-fixture | SKIPPED (sandbox) | - | - | - | - | - | - |

Then per-perspective details, one line per finding:
`<severity>/<confidence> <file>:<line> — <issue> → <CONFIRMED+FIXED | CONFIRMED+REPORT-ONLY | REFUTED (reason) | UNRESOLVED>`

## Environment variables

| Variable | Effect |
|----------|--------|
| `CODEX_REVIEW_BASE` | Override the base branch. Default: `git symbolic-ref refs/remotes/origin/HEAD` → fallback `main`. |
| `CODEX_REVIEW_REPO` | `cd` into this directory before running git ops. Without it, the caller's cwd is the review target. |

## Notes

- **Review target = caller's cwd**: the script does not `cd` unless `CODEX_REVIEW_REPO` is set. This skill is not dotfiles-specific.
- **Output contract**: run-review.sh returns validated JSON (schema-checked by `parse-review-output.sh`). Exit codes: 0 pass / 2 findings / 1 error / 3 sandbox skip / 4 rate-limit skip. Do NOT attempt to parse codex prose yourself; if you get exit 1, treat it as an error, not as PASS.
- **Model selection**: run-review.sh はモデルを指定しない — `codex/config.toml` の global 設定 (`model` / `model_reasoning_effort`) が唯一の選択点。観点別・リスク tier 別の切り替えは意図的に持たない (計測なしの最適化はしない)。必要になったら `codex exec -c model=... -c model_reasoning_effort=...` の per-call override で実現できる。
- **Why verify-then-fix**: cross-vendor reviewers have non-overlapping blind spots but also produce false positives; verification against the actual code filters them before they cost edit time. Detection is instructed to over-report ("report everything") and this skill filters downstream — do not skip verification because findings "look obviously right".
- **Do not commit** fixes from this skill.
- **Cost**: max 2 codex calls per perspective (detect + confirm), so max 6 calls for a full run. Confirm with the user before running on very large diffs.
- **Design: split file layout**: this skill's scripts live in `claude/skills/codex-review/scripts/`; the perspective prompts live in `codex/review-prompts/` (codex-facing content). The split is intentional — to tweak a perspective, edit the `.md` under `codex/review-prompts/`.
- **Running under a shell sandbox** (Claude Code の Bash sandbox 等): 外側シェルが `$HOME/.codex/` 配下の SQLite (`state_*.sqlite` / `goals_*.sqlite` / `memories_*.sqlite`) の write を allow していない場合、`codex` CLI 内部の in-process app-server client が state DB を open できず `failed to initialize in-process app-server client: Operation not permitted (os error 1)` で exit する。run-review.sh はこのシグネチャを検出して exit 3 (SKIP) を返す (ERROR ではなく明示的 skip)。回避策は 2 通り:
  1. **sandbox 外で実行** — user が別 terminal で `bash "$HOME/.claude/skills/codex-review/scripts/run-review.sh" <perspective>` を叩き、出力を PR body / evidence に paste。
  2. **Claude Code settings で許可を拡張** — `~/.claude/settings.json` の `permissions` で `~/.codex/**` を write allow に、network allowlist に `chatgpt.com` (auth mode = chatgpt の場合) または `api.openai.com` (API key の場合) を追加。ChatGPT auth では実 API call でも `chatgpt.com/backend-api/` を叩くため、SQLite だけでなく network 側も allow が必要。

  この dotfiles の `claude/settings.json` には回避策 2 を適用済み (`sandbox.filesystem.allowWrite` に `~/.codex`、`sandbox.network.allowedDomains` に `chatgpt.com`)。settings.json 未リンクのマシンでは回避策 1 にフォールバックする。write allow を SQLite ファイルに絞らずディレクトリ単位にしているのは、codex CLI が sessions/ / history.jsonl / log/ / auth.json (token refresh) 等にも書き込むため。`excludedCommands` に `codex *` を足す案は sandbox を丸ごと外すためより広く、path/domain を絞る現方式を採用。
