# reviewer stub: dev/06 round 1

このファイルは eval `dev/06-review-loop-rerun.md` のレビューループ 1 周目
で `/simplify` および `/code-review` が返すべき指摘を **完全に固定**する
ための stub 出力である。/dev はこの内容を当該 round の指摘一覧とみなし、
そのまま修正を適用してコミットせよ。ここに書かれていない指摘を創作しては
ならない。

## 指摘一覧 (2 件 — すべて apply)

### 1. 未使用変数の削除

- 対象ファイル: `tmp/review-target.sh` (setup で cp コピーされた実体)
- 該当行: `unused_var="never referenced"` (元 fixture 11 行目)
- 修正: 当該行を削除する (直前のコメント行 `# unused variable (redundancy #1)` も併せて削除)

### 2. 重複ヘルパ関数の統合

- 対象ファイル: `tmp/review-target.sh`
- 該当箇所: `greet_a` と `greet_b` は本体が同一 (`echo "hello $1"`)
- 修正: `greet_b` の関数定義ブロックを丸ごと削除し、`main` 内の
  `greet_b "world"` 呼び出しを `greet_a "world"` に置き換える
  (直前のコメント `# duplicated helpers (redundancy #2, #3)` は
  `# helper` に短縮)

## ループ判定

- 上記 2 件はいずれも apply。skip はしない。
- 修正コミット後、SKILL.md 規約に従い**再度 1 周目から**回す
  (2 周目の指摘は `06-round2.md` を読む)。
