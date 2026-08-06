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
| `type` | ○ | `decision` / `walkthrough` / `series` / `notes` / `diagram` |
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

## `notes` — 散文

型に嵌らない内容の逃げ道。`{ "type": "notes", "body": "..." }`。
多用するならページ全体が md 向きということなので、HTML にする判断自体を見直す。

## `diagram` — mermaid 図

`{ "type": "diagram", "mermaid": "graph TD;A-->B;" }`。
Artifact が mermaid をネイティブに描画する。画像を外部から読み込まない。
