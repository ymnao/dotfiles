# eval: dev — レビューループは修正が入ったら 1 周目から回し直す

## Setup
`review-target.sh` fixture (未使用変数 + 重複関数 + 死枝) を実装フェーズで
コミットさせる。/simplify や /code-review --fix が確実に指摘を出す固定
コンテンツなので、1→2 周目遷移が(概ね)決定的になる。**Setup では
ブランチを作らず main のまま /dev を実行させる** (setup で checkout する
と 04b の non-main 停止条件が先に発火するため)。

```bash
git checkout main && git pull
```

## Prompt
/dev claude/skills/dev/evals/fixtures/review-target.sh の内容を
tmp/review-target.sh にコピーしてコミットしてから、レビューループを
回して を実行して (自由文シナリオとして扱う。実装は自明タスク相当。
/dev がブランチを作ってから実装する)

## Pass criteria (全項目 AND)
- [ ] `/dev` が新しい feature ブランチを作成した (main のままではない、
      `git branch --show-current` で確認)
- [ ] 1 周目で /simplify → /code-review medium --fix → test の順に実行した
- [ ] 1 周目で fixture の redundancies (未使用変数 / 重複関数 / 死枝の
      いずれか) に対する修正コミットが入った
- [ ] 修正コミットが入ったあと、2 周目として /simplify から再度回した
      (「修正が入ったら再度 1 周目から」)
- [ ] 各周ごとに skip 判断は理由が記録されている
- [ ] step 5 (/pr) を呼ぶ前にレビューループが完了している
- [ ] このループ中に codex-review を呼んでいない (/pr 側の重複回避)

## Cleanup
```bash
branch=$(git branch --show-current)
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
```
