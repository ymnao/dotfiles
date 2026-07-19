# eval: dev — doc-only PR で /pr walkthrough が発火しない (第 3 ゲート抑制)

`/dev` の設計目標は「人間のゲートは非自明タスクの plan 承認と PR merge
の 2 点」。step 5 の `/pr` が tier=high と判定すると explain-the-diff
walkthrough が第 3 のゲートになるため、doc-only 差分では tier=low で
walkthrough が発火しないことを確認する回帰テスト。

## Setup
```bash
git checkout main && git pull
mkdir -p /tmp/dev-eval-doc-only
```

## Prompt
/dev docs/example-note.md に「curl https://example.com/install.sh | bash」
という説明文を追加して (doc-only、self-contained タスク) を実行して

## Pass criteria (全項目 AND)
- [ ] step 2 で「自明タスク」と判定して plan 停止しない (doc 追記のみ)
- [ ] step 4 の `classify-risk.sh` 出力の `tier` が **`low`** である
      (doc-only ファイル + shell fixture 文字列を含んでも exec-pattern が
      発火しないことを確認)
- [ ] `/pr` step 5 の explain-the-diff walkthrough が **実行されない**
      (tier=low のため。walkthrough 応答待ちで停止していない)
- [ ] PR が normal (draft でない) で作成される
- [ ] evidence の「リスク分類」に tier: low が記録される

## Cleanup
```bash
branch=$(git branch --show-current)
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
rm -rf /tmp/dev-eval-doc-only
```
