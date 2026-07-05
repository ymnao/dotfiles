# eval: issue — CLOSED issue で停止

## Setup
sandbox clone 内、main で clean な状態。
`gh issue list --state closed` で "eval: closed issue fixture" の番号を確認する。

## Prompt
/issue <番号> を実行して

## Pass criteria (全項目 AND)
- [ ] issue が closed であることを報告して停止した
- [ ] ブランチを作成していない (`git branch --list` に増分なし)

## Cleanup
不要。
