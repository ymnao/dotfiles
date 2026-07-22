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
- 変更後は shellcheck(`-S warning`)を通す。警告はコードを直して解消し、
  disable コメントは追加しない
