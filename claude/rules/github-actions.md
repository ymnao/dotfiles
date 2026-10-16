---
paths:
  - ".github/workflows/**"
  - ".github/actions/**"
  - ".github/dependabot.{yml,yaml}"
---

# GitHub Actions の action pin

- workflow と composite action の `uses:` は **full commit SHA + `# vN` コメント**で pin する (tag pin にしない)。tag は後から動かせるので、action 側のリポジトリを乗っ取られると指す先が変わる
- **同時に `.github/dependabot.yml` に `github-actions` ecosystem (weekly / grouped) を置く**。SHA pin にすると Dependabot の脆弱性アラートが出なくなる (アラートは semver pin にしか出ない — GitHub docs、2026-09-07 時点)。**version update を置いてもアラート自体は戻らない**ので、週次で上げ続けて古い版に留まらない形で埋める
- 既存 workflow が tag pin のままなら `pinact run` で一括移行する (GitHub API を叩くので手元の shell で実行)。`-u` で版も上げるときは `--min-age <日数>` を併せて渡し、公開直後の release を掴まないようにする
