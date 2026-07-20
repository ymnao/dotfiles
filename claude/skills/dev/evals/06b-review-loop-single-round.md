# eval: dev — レビューループは round=1 で指摘 0 なら 1 周で complete して終了する (reviewer stub 決定化)

## Setup
`review-target.sh` fixture を修正対象の実ファイルとして扱う。findings は
stub 化し、round=1 で 0 件を返すことで「1 周で complete して round=2 に
入らず終了」経路を必ず実行させる。
**Setup ではブランチを作らず main のまま /dev を実行させる**
(setup で checkout すると 04b の non-main 停止条件が先に発火するため)。

`git pull` は使わない (README の
[setup で `git pull` を実行しない](README.md#no-git-pull) 節参照)。

```bash
git checkout main
```

## Prompt

> **stub 契約適用**: `claude/skills/dev/evals/README.md` の
> [reviewer stub 契約](README.md#reviewer-stub-contract) に従い、この eval
> 実行中は SKILL.md step 4 の `/simplify` / `code-reviewer` を実起動せず、
> round=1 の指摘一覧として `fixtures/reviewer-stubs/06b-round1.md` を読む。
> 0 件のため修正コミットは作らず、round=1 の end で status=complete を
> 出してループを終える (round=2 には入らない)。

/dev claude/skills/dev/evals/fixtures/review-target.sh の内容を
tmp/review-single-target.sh にコピーしてコミットしてから、レビューループを
回して (自由文シナリオとして扱う。実装は自明タスク相当。
/dev がブランチを作ってから実装する)

## Pass criteria (全項目 AND)

機械検証可能 (transcript を `$transcript` として参照):
- [ ] `/dev` が新しい feature ブランチを作成した (main のままではない、
      `git branch --show-current` で確認)
- [ ] `tmp/review-single-target.sh` が commit された (実装コミット。
      レビューループでは fix コミットは 0 本)
- [ ] round=1 の各 phase が **正確に 1 回ずつ、start → stub-loaded → end
      の順** で出現している:
      [`#review-loop-phase-order`](README.md#review-loop-phase-order) awk で検証
      (round=1 のみが transcript に現れる想定で、awk は登場した round
      すべてを検査するため 06b でもそのまま使える)
- [ ] round=1 が「指摘 0 で完了」で終わった:
      `grep -qE '^\[dev/review-loop\] round=1 phase=end applied=0 status=complete head=[a-f0-9]+ dirty=[01]$' "$transcript"`
- [ ] stub-loaded ログが出て指摘件数が 0:
      `grep -qE '^\[dev/review-loop\] round=1 phase=stub-loaded stub=.*06b-round1\.md count=0$' "$transcript"`
- [ ] **★主目的**: round=2 の構造化ログが transcript に **1 行も存在しない**
      (round=1 complete で loop 終了、round=2 には入らないことを機械検証):

      ```bash
      ! grep -qE '^\[dev/review-loop\] round=2 ' "$transcript"
      ```
- [ ] round=1 で fix / commit / uncommitted change が **発生していない**
      (0 件 stub 遵守を機械検証。dev/07 round=2 と同型の head/dirty 比較):

      ```bash
      start_head=$(grep -oE '^\[dev/review-loop\] round=1 phase=start head=[a-f0-9]+ dirty=[01]$' "$transcript" | awk '{print $4" "$5}')
      end_head=$(grep -oE '^\[dev/review-loop\] round=1 phase=end applied=0 status=complete head=[a-f0-9]+ dirty=[01]$' "$transcript" | awk '{print $6" "$7}')
      [ -n "$start_head" ] && [ "$start_head" = "$end_head" ]
      ```

      (SKILL.md 構造化ログの `head=<sha>` `dirty=<0|1>` を文字列一致で
      比較。start と end で HEAD SHA と dirty 値の両方が同一なら、
      Bash / apply_patch / sed 経由も含めて round=1 中に新たな変更が
      入らなかったことを保証できる。dirty=0 を強制しないのは sandbox
      制約由来の pre-existing artifact により dirty=1 スタートも
      起こり得るため許容する (SKILL.md の「round=2 の head/dirty 不変」
      節と同型の緩和))
- [ ] このループ中に stub 契約対象の reviewer (`/simplify` slash command
      と `code-reviewer` サブエージェント) を **実起動していない**:
      [`review-loop-stub-not-invoked`](README.md#review-loop-stub-not-invoked) の 2 grep で検証

transcript 判定 (human runner):
- [ ] round=1 の指摘 0 件を受けて「レビューループは 1 周で完了」と
      会話ログに明示してから step 5 (/pr) へ進んでいる
- [ ] fixture 外の指摘を創作していない (stub の 0 件に従った)

## Cleanup
```bash
branch=$(git branch --show-current)
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
```
