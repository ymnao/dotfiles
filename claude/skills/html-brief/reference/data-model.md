# brief.json のデータモデル

`render.mjs` が受け取る JSON の仕様。**ここに無いキーは黙って無視されず、検証
エラーで落ちる** (`takeaways` のような 1 文字違いが黙殺されると、書いたはずの
内容が消えたことに publish 後まで気付けないため)。型が合わない場合も同様。

## トップレベル

| キー | 必須 | 内容 |
|---|---|---|
| `title` | ○ | ページ見出し。`<title>` と `<h1>` の両方になる (**この 2 つで文言をずらさないため、`title` ではインライン記法が効かない**) |
| `verdict` | ○ | **結論**。冒頭のボックスに入る。ここだけで判断が付く粒度で書く |
| `sections` | ○ | 1 件以上。下記の 5 型 |
| `date` | | 日付。`subject` と `·` で連結してメタ行になる |
| `subject` | | 対象 (repo 名 / PR 番号 / issue 番号など) |
| `lead` | | このページが何を判断させるためのものか 1-2 文 |
| `footer` | | 出典・測定条件・**未確認の項目**。未確認は未確認と書く |

文字列で効くインライン記法は `` `code` `` と `**bold**` の 2 つだけ
(リンク・見出し・箇条書きは効かず、そのまま出る)。`title` では効かない
(`<title>` と `<h1>` で文言をずらさないため)。空行で区切ると段落に分かれる。

## section 共通

| キー | 必須 | 内容 |
|---|---|---|
| `type` | ○ | 下記 12 型のいずれか |
| `title` | | 見出し (`<h2>`) |
| `details` | | `{ "summary": "...", "body": "..." }` — 長い根拠を折り畳む |

同じ型を何度使ってもよい (判断表を 2 つ並べる等)。

## `decision` — 判断ボード

選択肢が 3 つ以上あるとき、または各行に判定が付くときに使う。

```json
{
  "type": "decision",
  "columns": ["選択肢", "判定", "根拠"],
  "rows": [
    { "label": "A 案", "badge": { "kind": "ok", "text": "採用" }, "cells": ["根拠を 1 文で"] }
  ]
}
```

- `columns` は 2 列以上。**1 列目が対象、2 列目が判定**で固定
- `cells` は `columns.length - 2` 件。合わないと落ちる
- `badge.kind` は `ok` / `warn` / `stop` / `info` の 4 種のみ。`badge` を省くと空欄

## `walkthrough` — 手順・変更のウォークスルー

```json
{
  "type": "walkthrough",
  "steps": [
    { "title": "何を変えたか", "body": "なぜそうしたか", "code": "git diff --stat" }
  ]
}
```

`body` と `code` は任意。番号は render 側が振る。

## `series` — 実測データの推移

```json
{
  "type": "series",
  "unit": " 件",
  "labelHeader": "時点", "valueHeader": "値", "noteHeader": "備考",
  "points": [{ "label": "2026-01", "value": 123, "note": "何が起きたか" }],
  "takeaway": "数字から何が言えるか"
}
```

- `value` は 0 以上の数値。**バーの幅は最大値から render 側が算出する**
  (割合を推測して書かない)
- `takeaway` は**任意だが原則書く**(表だけで終わらせない)。レンダラは省略を
  拒否しない — 数字の意味づけは人が判断することなので、機械では強制しない
- `points[].parts` を書くとバーを内訳で塗り分け、凡例が付く。
  **合計が `value` と一致しないと検証エラー**(「一部だけ見せている」のか
  誤りなのか読者に区別が付かないため):

  ```json
  { "label": "2 周目", "value": 9, "parts": [
      { "label": "Critical", "value": 2, "kind": "stop" },
      { "label": "Warning",  "value": 7, "kind": "warn" }] }
  ```

## `notes` — 散文

型に嵌らない内容の逃げ道。`{ "type": "notes", "body": "..." }`。
多用するならページ全体が md 向きということなので、HTML にする判断自体を見直す。

## `diagram` — mermaid 図

`{ "type": "diagram", "mermaid": "graph TD;A-->B;" }`。
Artifact が mermaid をネイティブに描画する。画像を外部から読み込まない。

## `compare` — 2 カラム対比

入力/出力、変更前/後。**説明の中核は差分**なので、読者に頭の中で並べさせない。

```json
{
  "type": "compare",
  "left":  { "label": "変更前", "code": "Math.max(...values)" },
  "right": { "label": "変更後", "code": "values.reduce(...)", "codeLang": "plain" }
}
```

- `left` / `right` とも `label` が必須、`body` / `code` / `codeLang` は任意
- 狭い画面では 1 カラムに落ちる

## `links` — 出典・参照先

```json
{ "type": "links", "items": [{ "label": "PR #279", "url": "https://…", "note": "実装" }] }
```

- **`url` は `http(s)` のみ**。`javascript:` / `data:` 等は検証エラーで落ちる
- 本文中にリンクは書けない (インライン記法にリンクは無い)。参照はこの型に集める

## `callout` — 注意喚起

`{ "type": "callout", "kind": "warn", "body": "落とし穴の説明" }`。
`kind` は `ok` / `warn` / `stop` / `info` (既定)。**多用すると全部が目立たなくなる**。

## `definitions` — 用語の定義

`{ "type": "definitions", "items": [{ "term": "Tier1", "body": "壊れるもの" }] }`。
`term` と `body` の両方が必須。

## `checklist` — チェックリスト

```json
{ "type": "checklist", "items": [{ "label": "済んだ項目", "checked": true, "note": "備考" }] }
```

`checked` は真偽値 (既定 `false`)。静的ページなので**読者が触れるものではない** — 現状を示すために使う。

## `tiles` — 数値サマリ

`{ "type": "tiles", "items": [{ "label": "テストケース", "value": 56, "note": "備考" }] }`。
`value` は文字列か数値。規模感を先に掴ませたいときだけ使う (結論ボックスと役割が競合するので置きすぎない)。

## `timeline` — 経緯

`{ "type": "timeline", "items": [{ "when": "2026-08-06", "title": "…", "body": "…" }] }`。
`walkthrough` が「手順」なのに対し、こちらは**いつ何が起きたか**。番号は振らない。

## コードブロックの `codeLang`

`walkthrough.steps[]` と `compare` の左右で使える。値は `plain` (既定) か `diff` のみ。

`diff` にすると**行頭 1 文字だけ**で色を分ける (`+` 追加 / `-` 削除 / `@@` hunk /
`+++` `---` `diff ` メタ)。構文解析はしないので、言語別のハイライトは無い。
