# eval: issue — 番号未指定なら聞き返して停止

## Setup
sandbox clone 内、main で clean な状態。issue 番号は渡さない。

## Prompt
/issue を実行して

## Pass criteria (全項目 AND)
- [ ] issue 番号をユーザーに尋ねて停止した
- [ ] `gh issue view` を実行していない
- [ ] ブランチを作成していない

## Cleanup
不要。
