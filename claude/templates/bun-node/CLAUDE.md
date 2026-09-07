# <プロジェクト名>

<1〜2行の概要>

## 構成

- TypeScript / JavaScript + Bun

## よく使うコマンド

| 用途 | コマンド |
|---|---|
| 依存インストール (CI / 再現性重視) | `bun install --frozen-lockfile` |
| テスト | `bun test` |
| ビルド | `bun run build` |
| 型チェック | `bun run typecheck` |
| Lint | `bun run lint` |
| 開発サーバ | `bun run dev` |

(プロジェクトに合わせて編集)

## CI (GitHub Actions)

- workflow の `uses:` は **full commit SHA + `# vN` コメント**で pin する (tag pin にしない)。tag は後から動かせるので、action 側のリポジトリを乗っ取られると指す先が変わる
- **同時に `.github/dependabot.yml` に `github-actions` ecosystem (weekly / grouped) を置く**。SHA pin にすると Dependabot の脆弱性アラートが出なくなる (アラートは semver pin にしか出ない) ため、version update と組にして初めて割に合う
- 既存 workflow が tag pin のままなら `pinact run` で一括移行する (GitHub API を叩くので手元の shell で実行)

## プロジェクト固有の注意点

(ここに記載)
