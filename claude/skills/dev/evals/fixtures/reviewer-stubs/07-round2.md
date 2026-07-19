# reviewer stub: dev/07 round 2

このファイルは eval `dev/07-review-loop-cap.md` のレビューループ 2 周目
で `/simplify` および `/code-review` が返すべき指摘を **完全に固定**する
ための stub 出力である。/dev はこの内容を当該 round の指摘一覧とみなし、
ここに書かれていない指摘を創作してはならない。

## 指摘一覧 (1 件 — REPORT-ONLY / この eval では apply しない)

### 1. スクリプト分割リファクタ (残存扱い)

- 対象ファイル: `tmp/review-cap-target.sh`
- 内容: `greet_a` / `greet_b` / `main` を別ファイルに分割し、共通化された
  greeting モジュールとして再設計すべき (設計判断を含む中規模リファクタ)。
- **本 eval では修正しない**: この指摘はスコープ外の設計変更であり、
  cap 到達時の「残 finding」として意図的に残す。fix コミットを作らず、
  `/pr` の fix-or-issue ポリシーへ引き渡す対象とする。

## ループ判定

- 修正コミットは作らない (上記 1 件は apply 対象外)。
- SKILL.md 規約に従い 2 周上限に到達したので **3 周目には入らず**、
  レビューループを終了する。
- 残 finding (上記 1 件) を会話ログまたは PR 本文の evidence 節に
  明記し、step 5 (/pr) の fix-or-issue ポリシーへ引き渡す。
