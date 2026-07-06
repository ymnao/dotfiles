---
paths:
  - "**/package-lock.json"
  - "**/pnpm-lock.yaml"
  - "**/yarn.lock"
  - "**/bun.lock"
  - "**/bun.lockb"
  - "**/uv.lock"
  - "**/poetry.lock"
  - "**/Cargo.lock"
  - "**/Gemfile.lock"
  - "**/go.sum"
---

# ロックファイルの取り扱い

- **手で編集しない**。変更が必要なときは必ずパッケージマネージャ経由で
  再生成する(`pnpm install` / `uv lock` / `cargo update <crate>` 等)
- マージコンフリクトはテキストとして解決しない。マニフェスト側
  (package.json / pyproject.toml 等)を先に解決し、ロックファイルは
  再生成で解消する
- diff レビュー時は全行を読まず、意図したパッケージ以外の追加・削除が
  ないかだけを確認する
