---
name: html-brief
description: 調査結果・比較・設計変更のウォークスルー・実測データを、固定デザインの HTML 1 枚ページにして Artifact として publish する。user が「HTML で」「ページで」「ブラウザで見たい」と明示したときだけ使う。通常の報告・レビュー結果・plan の提示は Markdown のままにする
---

長い Markdown は人間には読み返しのコストが高い。選択肢が 3 つ以上ある判断や
時系列データを、**先に「どれを見るか」を決められる形**で出すための skill。

**HTML を手で書かない。** 書くのは意味だけ (`brief.json`)。見せ方 —
CSS・エスケープ・バーの幅・表の整合 — は `render.mjs` が決定的に組み立てる。
これで出力トークンが中身の量だけで決まり、ページ間で見た目がぶれない。

## 使う / 使わない

**使う**: user が HTML / ページ / ブラウザでの提示を明示的に求めたとき。
想定は 3 つ — (a) 調査・比較結果の行き先を示す判断ボード、(b) 大きめの diff や
設計変更のウォークスルー、(c) 実測データの推移。

**使わない**: 通常の作業報告、レビュー結果、plan の提示、PR 本文、issue 本文、
HANDOFF.md。これらは Markdown のままにする。**指示が無いのに HTML にしない** —
チャットに直接書けば済むものをページにすると、かえって往復が増える。

## Steps

1. `reference/data-model.md` (この SKILL.md と同じディレクトリ) を読む。
   section は `decision` / `walkthrough` / `series` / `notes` / `diagram` の 5 型
2. scratchpad に `brief.json` を書く。**結論 (`verdict`) だけで判断が付く粒度**に
   すること。本文を読まないと結論が分からないページは、md を読み返すのと同じコスト
3. `node <skill dir>/render.mjs brief.json out.html` で HTML を生成する
4. 検証エラーが出たら **JSON を直す**。HTML を直接いじって回避しない
5. `Artifact` ツールで `out.html` を publish し、URL を user に渡す。
   同じページを更新するときは**同じファイルパスで再 deploy**する (パスを変えると別 URL)

## 制約

- **HTML / CSS を書かない**。表現が足りないと感じたら `notes` 型で散文にするか、
  それでも足りなければ skill 側の PR として `style.css` / `render.mjs` を直す
- `style.css` と `render.mjs` は **repo の正本**。ページごとに書き換えない
- `brief.json` と生成した HTML は scratchpad に置く。**repo にコミットしない**
- 図は `diagram` 型 (mermaid)。画像を外部から読み込まない

## 注意

- `frontend-design` skill とは目的が逆 — あちらは「毎回違う美的方向性で
  production の UI を作る」ためのもの。こちらは固定。混ぜない
- レンダラは Node の標準ライブラリだけで動く (依存追加なし)。
  回帰テストは `tests/html-brief/`、`make test` から実行される
