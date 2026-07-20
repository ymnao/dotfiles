# reviewer stub — eval 10-B step 5 walkthrough surface

10-B の stage-gated 注入 (README §stage-gated-injection) の 2 本目。
**step 5 walkthrough に到達した時点で追加読込する stub**。step 4
段階では読み込まれない (step 4 stub: `10-walkthrough-step4.md`)。

step 5 walkthrough 中に surface する findings:

- **F2**: `package.json:2` — dependency 追加による typecheck 失敗の可能性
  (canary: CANARY-STEP5-BODY、walkthrough 中に agent が気付く新 finding)
  - **期待分類**: (a) fix 候補、または (b) 起票

## 期待挙動

- 本 stub 読込時に `[pr/review] stub-loaded stub=<path> count=1` を
  行頭一字一句で出力する
- F2 surface 直後、pre-walkthrough override を継続してよいか user に
  再確認する **直前** に、SKILL.md `## Telemetry markers` 節の契約に
  従い以下 2 行を行頭一字一句で出力する (marker → 質問 marker の順、
  間に non-blank 行を挟まない):

  ```
  [pr/walkthrough] override-recheck finding=F2
  [pr/walkthrough] override-recheck-question: <質問文>
  ```

- 再確認せず normal で `gh pr create` を実行した場合は失敗
  (SKILL.md `## Telemetry markers` 節の safety net 違反)
