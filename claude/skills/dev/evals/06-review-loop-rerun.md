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
> 実行中は SKILL.md step 4 の `/simplify` / `/code-review` を実起動せず、
> N 周目の指摘一覧として `fixtures/reviewer-stubs/06-round<N>.md` を読む。
> 各周で修正コミット後にテストスイート (`make test` 等) を実行し、pass を
> 確認したログを会話に残すこと (SKILL.md step 4 準拠)。

/dev claude/skills/dev/evals/fixtures/review-target.sh の内容を
tmp/review-target.sh にコピーしてコミットしてから、レビューループを
回して を実行して (自由文シナリオとして扱う。実装は自明タスク相当。
/dev がブランチを作ってから実装する)

## Pass criteria (全項目 AND)

機械検証可能:
- [ ] `/dev` が新しい feature ブランチを作成した (main のままではない、
      `git branch --show-current` で確認)
- [ ] `tmp/review-target.sh` が commit され、その後 round1 stub の 2 件
      (未使用変数削除 + 重複関数統合) に対応する fix コミットが 1 本以上入った
- [ ] レビューループが **正確に 2 周** 回った (3 周目に入っていない、
      round2 stub の「指摘 0 で完了」に従った)
- [ ] 最終時点で `bash -n tmp/review-target.sh` が exit 0 (構文的に正常)
- [ ] 最終時点で `bash tmp/review-target.sh` の stdout が `hello world` を
      含む行を **正確に 2 回** 出力する (`bash tmp/review-target.sh | grep -c '^hello world$'`
      が `2`。round1 fix の重複関数統合が動作を壊していないことを直接検証)

transcript 判定 (human runner):
- [ ] 1 周目で round1 stub を読み、記載された 2 件を apply した
      (skip はしない、fixture 外の指摘を創作していない)
- [ ] 修正コミット後、2 周目を **round1 から** 再開した (「修正が入ったら
      再度 1 周目から」の SKILL.md 規約準拠)
- [ ] 2 周目で round2 stub を読み、指摘 0 として完了ログを出してから
      step 5 (/pr) へ進んだ
- [ ] 各周で修正コミット後にテストスイート (`make test` 等) を実行し
      pass を確認したログが会話に残っている (SKILL.md step 4 準拠)
- [ ] このループ中に `/simplify` や `/code-review` を **実起動していない**
      (stub 契約遵守)
- [ ] このループ中に codex-review を呼んでいない (/pr 側の重複回避)

## Cleanup
```bash
branch=$(git branch --show-current)
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
```
