# eval: dev — レビューループは修正が入ったら 1 周目から回し直す (reviewer stub 決定化)

## Setup
`review-target.sh` fixture (未使用変数 + 重複関数 + 死枝) を修正対象の
実ファイルとして扱う。ただしレビューの findings は完全 stub 化する
(下記 Prompt の stub 契約参照)。**Setup ではブランチを作らず main の
まま /dev を実行させる** (setup で checkout すると 04b の non-main
停止条件が先に発火するため)。

```bash
git checkout main && git pull
```

## Prompt

> **stub 契約 (この eval 実行中は SKILL.md step 4 を以下で置換する)**:
> レビューループの step 4 で `/simplify` と `/code-review` を **実際には
> 起動しない**。代わりに N 周目のレビュー結果として
> `claude/skills/dev/evals/fixtures/reviewer-stubs/06-round<N>.md` を読み、
> その内容を当該 round の指摘一覧とみなして修正を適用し、ループ判定
> (指摘あり → 再周回 / なし → 完了) は SKILL.md 規約どおり続行せよ。
> fixture に書かれていない指摘を創作しないこと。tests (`make test` 等)
> は round ごとに実行してよい。

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

transcript 判定 (human runner):
- [ ] 1 周目で round1 stub を読み、記載された 2 件を apply した
      (skip はしない、fixture 外の指摘を創作していない)
- [ ] 修正コミット後、2 周目を **round1 から** 再開した (「修正が入ったら
      再度 1 周目から」の SKILL.md 規約準拠)
- [ ] 2 周目で round2 stub を読み、指摘 0 として完了ログを出してから
      step 5 (/pr) へ進んだ
- [ ] このループ中に `/simplify` や `/code-review` を **実起動していない**
      (stub 契約遵守)
- [ ] このループ中に codex-review を呼んでいない (/pr 側の重複回避)

## Cleanup
```bash
branch=$(git branch --show-current)
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
```
