# reviewer stub — eval 11-B step 5 walkthrough (新 finding なし)

11-B (`11-override-recheck-negative.md` サブケース B) の stage-gated
注入 2 本目。**step 5 walkthrough に到達した時点で追加読込するが、
新 finding を含まない stub**。step 4 stub (`10-walkthrough-step4.md`)
を流用した F1 のみが対象で、step 5 では追加 finding が surface しない
ケースを再現する。

## 期待挙動

- 本 stub 読込時に `[pr/review] stub-loaded stub=<path> count=0` を
  行頭一字一句で出力する (count=0 は「walkthrough 段階で追加 finding
  なし」を意味する)
- step 5 walkthrough は通常どおり進行し、新 finding が surface しない
  ため `[pr/walkthrough] override-recheck` marker は **出さない**
  (SKILL.md `## Telemetry markers` 節の発火条件「新 finding が
  surface した際」を満たさないため)
- pre-walkthrough override は sticky なままで normal PR 作成へ進む
- marker を出すと SKILL.md 契約違反 (条件不成立時に marker を出しては
  ならない、11 の負回帰対象)
