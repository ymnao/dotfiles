---
paths:
  - "**/*.sh"
  - "**/*.bash"
---

# Shell スクリプト規約

- **bash 3.2 互換で書く**(macOS 標準)。連想配列(`declare -A`)、
  `${var,,}` / `${var^^}`、`readarray` は使わない。小文字化は
  `tr '[:upper:]' '[:lower:]'` を使う
- **BSD / GNU 両対応で書く**。`sed -i` は使わない(引数仕様が非互換)。
  `grep -P` は使わない(`-E` を使う)。`date -d` / `stat -c` 等の
  GNU 拡張を避ける
- 新規スクリプトは `set -euo pipefail` から始める。exit code を自分で
  扱うスクリプトは `set -uo pipefail` にして理由をコメントに書く
- 変数展開は常に quote する(`"$var"`)。word splitting に依存しない
- **日本語などの多バイト文字が直後に続く変数展開は必ず `${VAR}` とブレースで
  囲む**。bash 3.2 + UTF-8 ロケールでは多バイト文字の一部バイトが変数名に
  取り込まれ、未定義変数として誤パースされる(`set -u` だと即死)
- **ロケール依存のあるテスト・スクリプトはロケールを明示 pin し、理由コメントを
  書く**(ambient ロケール頼みにしない)。バイト同一性を検査する箇所(BSD awk
  の `==`、日本語文字列比較、sort 順依存等)は `LC_ALL=C` 固定、逆に「UTF-8
  ロケール下での挙動」を回帰検査したい箇所は `LC_ALL=en_US.UTF-8` 等を明示
  pin する。pin の粒度は次のどちらでもよい:
  (a) shebang 直下で `export LC_ALL=...` — スクリプト全体が同じロケールに
      依存する場合 (実例: `tests/agents-md-sync/run-agents-md-sync-check.sh`)
  (b) ケース単位で `LC_ALL=... command args` 形式で行スコープ pin — 特定
      ケースだけ非デフォルトロケールを検査したい場合 (実例:
      `tests/verify-ci/run-verify-ci-tests.sh` の `stderr-defer-policy-utf8`
      ケース = `LC_ALL=en_US.UTF-8`)。
  CI は `make test` を LC_ALL matrix で 3 ロケール並列に回すため、pin 忘れは
  多くの場合 matrix job のどれかで fail する(issue #181)。ただし matrix の
  自動検出は「テストのアサーションが結果差を assert する」ケースに限る:
  silent に間違った値を返してもテスト側が拾わないパス、あるいは matrix に
  含まれない特殊ロケール(`ja_JP.SJIS` 等)固有の依存は matrix でも素通しに
  なるため、規約としての pin は依然必要
- 変更後は shellcheck(`-S warning`)を通す。警告はコードを直して解消し、
  disable コメントは追加しない
