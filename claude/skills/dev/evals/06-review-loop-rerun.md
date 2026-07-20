# eval: dev — レビューループは修正が入ったら 1 周目から回し直す (reviewer stub 決定化)

## Setup
`review-target.sh` fixture (未使用変数 + 重複関数 + 死枝) を修正対象の
実ファイルとして扱う。ただしレビューの findings は完全 stub 化する
(下記 Prompt の stub 契約参照)。**Setup ではブランチを作らず main の
まま /dev を実行させる** (setup で checkout すると 04b の non-main
停止条件が先に発火するため)。

`git pull` は使わない (README の
[setup で `git pull` を実行しない](README.md#no-git-pull) 節参照)。

```bash
git checkout main
```

## Prompt

> **stub 契約適用**: `claude/skills/dev/evals/README.md` の
> [reviewer stub 契約](README.md#reviewer-stub-contract) に従い、この eval
> 実行中は SKILL.md step 4 の `/simplify` / `code-reviewer` を実起動せず、
> N 周目の指摘一覧として `fixtures/reviewer-stubs/06-round<N>.md` を読む。
> 各周で修正コミット後にテストスイート (`make test` 等) を実行し、pass を
> 確認したログを会話に残すこと (SKILL.md step 4 準拠)。

/dev claude/skills/dev/evals/fixtures/review-target.sh の内容を
tmp/review-target.sh にコピーしてコミットしてから、レビューループを
回して を実行して (自由文シナリオとして扱う。実装は自明タスク相当。
/dev がブランチを作ってから実装する)

## Pass criteria (全項目 AND)

機械検証可能 (transcript を `$transcript` として参照):
- [ ] `/dev` が新しい feature ブランチを作成した (main のままではない、
      `git branch --show-current` で確認)
- [ ] `tmp/review-target.sh` が commit され、その後 round1 stub の 2 件
      (未使用変数削除 + 重複関数統合) に対応する fix コミットが 1 本以上入った
- [ ] 各 round の 各 phase が **正確に 1 回ずつ、start → stub-loaded → end
      の順** で出現している (重複・順序不整合の transcript を弾く):
      [`#review-loop-phase-order`](README.md#review-loop-phase-order) awk で検証
- [ ] round=1 が「指摘 2 件 apply → 次周へ」で終わった:
      `grep -qE '^\[dev/review-loop\] round=1 phase=end applied=2 status=continue head=[a-f0-9]+ dirty=[01]$' "$transcript"`
- [ ] round=2 が「指摘 0 で完了」で終わった:
      `grep -qE '^\[dev/review-loop\] round=2 phase=end applied=0 status=complete head=[a-f0-9]+ dirty=[01]$' "$transcript"`
- [ ] 各周で stub-loaded ログが出て指摘件数が期待どおり:
      `grep -qE '^\[dev/review-loop\] round=1 phase=stub-loaded stub=.*06-round1\.md count=2$' "$transcript"` および
      `grep -qE '^\[dev/review-loop\] round=2 phase=stub-loaded stub=.*06-round2\.md count=0$' "$transcript"`
- [ ] このループ中に `/simplify` `/code-review` `codex-review` slash
      command を **実起動していない**:
      [`review-loop-stub-not-invoked`](README.md#review-loop-stub-not-invoked) grep で検証
- [ ] `bash tmp/review-target.sh | grep -c '^hello world$'` が `2`
      (round1 fix の重複関数統合が動作を壊していないことを直接検証。
      構文エラーなら stdout 0 行になるので構文チェックも含意)

transcript 判定 (human runner):
- [ ] 各周で修正コミット後にテストスイート (`make test` 等) を実行し
      pass を確認したログが会話に残っている (SKILL.md step 4 準拠、
      test コマンドの出力形式が不定のため機械化しない)
- [ ] fixture 外の指摘を創作していない (stub の 2 件のみに従った)

## Cleanup
```bash
branch=$(git branch --show-current)
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
```
