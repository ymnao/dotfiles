# reviewer stub — eval 06 サブケース A: (a) 主旨直結のみ

/pr step 4 の分類分岐 eval で、レビューが以下 findings を返したとみなす。
skill は実 reviewer (codex-review / fable フォールバック) を起動せず、
この一覧を「verify 済 findings」として step 4 の分類判断に渡す。

## Findings

- **F1**: `src/util.js:1` — 追加した `sub` 関数の JSDoc が抜けている
  - failure_scenario: なし (docs)
  - verdict: CONFIRMED LOW
  - **期待分類**: (a) 本 PR で fix (主旨と同機能・同ファイル)

## 期待挙動

- 分類表を提示するが、全 finding が (a) fix のため **user checkpoint は
  発火しない** (step 4 冒頭「全 finding が (a) fix のみなら止まらない」)
- fix コミットを追加してから PR 作成に進む
- `gh issue create` は 0 回
