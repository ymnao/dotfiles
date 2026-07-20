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
   - **Fix-or-issue-or-dismiss ポリシー (三択)**: レビューで確認された finding の行き先は次の 3 つ。スコープ距離 (主旨との近さ) で振り分ける。「起票せず次セッションに暗黙持ち越し」は不可(verify-ci-before-pr hook も body 内の `defer(未起票)` を検出すると `gh pr create` をブロックする。ただし hook が検証するのは marker 有無のみで、(c) 対応しない の許可条件や user 承認の実在は hook では検証されない — skill 遵守で担保する):
     - **(a) 本 PR で fix**: スコープ距離「直結 (主旨と同機能・同ファイル)」、または CONFIRMED HIGH で本 PR スコープ内
     - **(b) issue 起票して追跡**: スコープ距離「隣接 (主旨外だが関連)」以上。同一根本原因 (共通 helper 欠如 / eval 未整備 等) から派生する finding が **2 件以上**あれば 1 本の統合 issue にまとめる (body に個別 finding を列挙)。1 件のみなら単独起票。総量ベース閾値 (N 件超で自動統合) は使わない(同根性のない finding を無理に束ねると追跡不能)
     - **(c) 対応しない**: 次の 3 条件のいずれかに該当するときのみ許可。**該当しなければ (b) が default**。曖昧な「後でやる」で (c) にするのは不可
       1. nit / スタイル好みで既存コードベースの一般許容水準内
       2. 指摘は正しいが修正コスト > 便益が明白 (使い捨てスクリプト等)
       3. codex-review verdict が CONFIRMED だが confidence が低め、または内容が false-positive 寄りと再判断された
   - **user チェックポイント (必須ゲート)**: (b) or (c) の候補が **1 件でもあれば**、下記の分類表を 1 turn 提示して user 承認を待つ。全 finding が (a) fix のみなら止まらない
     - 分類表フォーマット:
       ```
       | # | Finding (file:line — summary) | 行き先 | 根拠 |
       |---|---|---|---|
       | 1 | path/to/f.sh:42 — quoting 抜け | (a) fix | 主旨直結 |
       | 2 | path/to/g.sh:10 — eval 未整備 | (b) 統合 issue #N | 同根 (finding 3 と統合) |
       | 3 | path/to/i.sh:88 — eval 未整備 | (b) 統合 issue #N | 同根 (finding 2 と統合) |
       | 4 | path/to/h.sh:5 — コメント幅 | (c) 対応しない | nit / 一般許容水準内 |
       ```
     - user の応答が「OK」「進めて」等の明示承認なら分類確定 → 起票 → PR 作成へ。個別修正の指示があれば反映して再提示。この user 承認が (c) の「user 指示」記録および hook 通過書式「追跡しない (user 指示: <承認要約>)」の根拠になる
   - Draft 判定は **PR-level triage** で行う(codex-review の per-finding 分類 `REPORT-ONLY` / `UNRESOLVED` を pr の draft 判定に自動流用しない。用語の定義は `$HOME/.claude/skills/codex-review/SKILL.md` を参照)。**上から順に評価し、最初に一致した bullet を採用**する。bullet 内の処理で state が変わった場合(起票成功で URL が付いた等)は変更後の state で bullet 1 から**再評価する**。いずれの判定でも根拠と該当 finding を evidence に記録する:
     - **本 PR で fix すべき finding (a) が残っている**(未対応、または blocker として判断保留): **draft** で作成
     - **(b) 起票対象があり、追跡 issue URL が未起票**: 上記チェックポイントで user 承認済みの分類表に従い起票する。finding (または同根統合単位) ごとに一時ファイル(例: `$TMPDIR/pr-issue-body-<n>.md`)へ body を書き出し、`gh issue create --title "<title>" --body-file <path>` で起票する。**title は finding 原文の verbatim 転記ではなく agent が書き直した平文要約**とし、`"` / `` ` `` / `$` / `\` / `$()` を含めない(finding 原文由来の記号がシェル文字列に展開されると command injection になるため。原文の failure_scenario 等は body-file 側にのみ書く — body-file 経由は shell 展開を通らない)。起票完了後 (成功・失敗とも) に一時 body ファイルは `rm` で削除する (finding 内容の残留防止)。body には `finding の failure_scenario と該当 file:line 抜粋、リンク元 PR/branch` を含める(統合 issue の場合は個別 finding を箇条書きで列挙)。成功分の URL を evidence 追跡先に記載 → bullet 1 から再評価。失敗時(auth / perms / archived / repo 未指定 等)は **draft** に退避し 根拠 `step 4 pending`(起票失敗、user 対応待ち)を記録
     - **(c) 対応しない finding が 1 件以上ある**((b) 起票済 URL との混在も含む。(a) 未 fix が残っていないことは bullet 1 で判定済): **normal** で作成する。(c) の追跡先 URL 欄に「追跡しない (user 指示: <承認要約>)」と書く(`defer(未起票)` marker は使わない — hook が block するため)。根拠に `step 4 dismiss` を記録
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
7. Run `git push -u origin <branch_name>` (no-op if origin is already up to date; also syncs review-fix commits made after an early push). If the push is rejected as non-fast-forward (origin advanced independently), do NOT force push — report the divergence to the user and stop
8. Create the PR with `gh pr create`. Add `--draft` when step 4 **or** step 5 decided draft (draft-wins). **Exception**: user が PR 作成前の任意の時点(step 5 の walkthrough 応答 / それ以前 いずれも可、tier を問わない)で「step 4 の draft 判定は別 PR で追う。normal で作って」等、draft 判定を明示的に override する指示を出した場合は normal で作成し、その override 内容(受け取った user 指示の要約と受け取った step)を evidence の Draft 判定に記録する。**制約**: normal override でも hook の defer 検査は bypass されないため、未起票 finding が残ったまま normal 化するには (b) 起票または (c) dismiss (「追跡しない (user 指示: <要約>)」の記録) が前提。marker 文字列 `defer(未起票)` を残すと hook が block して deadlock になる。If `linked_issue` exists, include `Closes #<number>` in the body. ただし **tier=high で override が step 5 前に受け取られた場合**、step 5 walkthrough で新 finding が surface した際は override 継続意思を user に再確認する(walkthrough で見えた新事実に対して pre-walkthrough override が sticky にならないよう safety net)。この再確認質問を出す **直前** に、以下を **行頭一字一句この形式** で応答テキストに出力する(前後に装飾を付けない、`<id>` は再確認対象の新 finding 識別子):

   ```
   [pr/walkthrough] override-recheck finding=<id>
   ```

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
<本 PR で fix しない finding ((b) 起票 / (c) 対応しない) を列挙。0 件なら「なし」とだけ書き、表は省略。Finding 列は `file:line — 短い summary(30 字以内)` の compound identifier で書く(codex-review Report format 表には file:line 列が無く、参照だけでは同定不能なため、短い summary を併記して人間可読性を確保)。URL 列は (b) なら起票済み issue URL、(c) なら「追跡しない (user 指示: <承認要約>)」を書く。normal PR で `defer(未起票)` を残すのは不可 — hook が block する。draft のみ `defer(未起票)` を許容(起票失敗 = step 4 pending の一時待避)>

| Finding (file:line — summary) | 行き先 | URL / 記録 |
|---|---|---|
| <file:line — short summary> | (b) 統合 issue / (c) 対応しない | <issue URL または `追跡しない (user 指示: …)` または `defer(未起票)`(draft 限定)> |

## Draft 判定
- 判定: <normal / draft>
- 根拠: <step 4 / step 4 pending / step 4 dismiss / step 5 / step 8 override> — <理由と該当 finding>
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
| Draft 判定 | <normal / draft> — <step 4 / step 4 pending / step 4 dismiss / step 5 / step 8 override, 理由> |
