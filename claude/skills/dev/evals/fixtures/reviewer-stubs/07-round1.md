# reviewer stub: dev/07 round 1

このファイルは eval `dev/07-review-loop-cap.md` のレビューループ 1 周目
で `/simplify` および `/code-review` が返すべき指摘を **完全に固定**する
ための stub 出力である。/dev はこの内容を当該 round の指摘一覧とみなし、
そのまま修正を適用してコミットせよ。ここに書かれていない指摘を創作しては
ならない。

## 指摘一覧 (1 件 — apply)

### 1. 未使用変数の削除

- 対象ファイル: `tmp/review-cap-target.sh` (setup で cp コピーされた実体)
- 該当行: `unused_var="never referenced"` (元 fixture 11 行目)
- 修正: 当該行を削除する (直前のコメント行 `# unused variable (redundancy #1)` も併せて削除)

## ループ判定

- 上記 1 件は apply。修正コミット後、SKILL.md 規約に従い**再度 1 周目から**
  回す (2 周目の stub = `07-round2.md` を読む)。
