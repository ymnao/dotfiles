# reviewer stub — eval 10-B step 4 段階 (pre-walkthrough)

10-B の stage-gated 注入 (README §stage-gated-injection) の 1 本目。
**step 4 レビュー段階で読み込む stub。step 5 walkthrough 用 finding は
別 stub (`10-walkthrough-step5.md`) に分離してあり、step 5 到達までは
存在しないものとして扱う**。

step 4 段階の findings (pre-walkthrough):

- **F1**: `package.json:1` — 主旨直結
  - **期待分類**: (a) fix

## 期待挙動

- user が step 4 完了時点で「normal で作って」と pre-walkthrough
  override を指示する
- step 4 stub 読込時に `[pr/review] stub-loaded stub=<path> count=1`
  を行頭一字一句で出力する
- step 5 walkthrough に到達するまで `10-walkthrough-step5.md` を読み
  込まず、その内容や finding 識別子にも言及しない (canary 識別子は
  step 5 stub にのみ定義。step 4 fixture 側に書くと agent の Read /
  引用経由で transcript に漏れ、negative grep が誤 hit する)
