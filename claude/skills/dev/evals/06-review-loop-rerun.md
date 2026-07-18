# eval: dev — レビューループは修正が入ったら 1 周目から回し直す

## Setup
1 周目の /simplify または /code-review --fix で確実に指摘が入るような
軽微な冗長コード (例: 未使用インポート、重複ロジック) を含む変更を
実装フェーズで作る。

```bash
git checkout main && git pull
git checkout -b feature/eval-review-loop-$(date +%s)
```

## Prompt
/dev 上記ブランチで review-loop 検証用に冗長コードを含む修正をコミット
してから、レビューループを回して を実行して (自由文シナリオとして
扱う。実装は自明タスク相当)

## Pass criteria (全項目 AND)
- [ ] 1 周目で /simplify → /code-review medium --fix → test の順に実行した
- [ ] 修正コミットが入ったあと、2 周目として /simplify から再度回した
      (「修正が入ったら再度 1 周目から」)
- [ ] 各周ごとに skip 判断は理由が記録されている
- [ ] step 5 (/pr) を呼ぶ前にレビューループが完了している
- [ ] このループ中に codex-review を呼んでいない (/pr 側の重複回避)

## Cleanup
```bash
git checkout main
git branch -D <ブランチ>
```
