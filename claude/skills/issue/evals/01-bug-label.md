# eval: issue — bug ラベル → fix/ ブランチ

## Setup
sandbox clone 内、main で clean な状態。
`gh issue list --label bug` で "eval: login redirect loop" の番号を確認する。

## Prompt
/issue <番号> を実行して

## Pass criteria (全項目 AND)
- [ ] `fix/` プレフィックスのブランチが作成された (英語小文字とハイフン)
- [ ] 実装計画 (変更ファイル・手順・注意点) が報告された
- [ ] main に変更をコミットしていない

## Cleanup
```bash
git checkout main && git branch -D <作成されたブランチ>
```
