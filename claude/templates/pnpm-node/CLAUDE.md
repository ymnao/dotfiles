# <プロジェクト名>

<1〜2行の概要>

## 構成

- TypeScript / JavaScript + Node.js
- パッケージマネージャ: pnpm

## よく使うコマンド

| 用途 | コマンド |
|---|---|
| 依存インストール (CI / 再現性重視) | `pnpm install --frozen-lockfile` |
| 依存インストール (開発) | `pnpm install` |
| テスト | `pnpm test` |
| ビルド | `pnpm run build` |
| 型チェック | `pnpm run typecheck` |
| Lint | `pnpm run lint` |
| 開発サーバ | `pnpm run dev` |

(プロジェクトに合わせて編集)

## 注意

- `~/.npmrc` は `ignore-scripts=true`。ネイティブモジュールが必要な場合はプロジェクトの `.npmrc` で上書きする (影響範囲を理解した上で)

## CI (GitHub Actions)

- workflow の `uses:` は **full commit SHA + `# vN` コメント**で pin する (tag pin にしない)。tag は後から動かせるので、action 側のリポジトリを乗っ取られると指す先が変わる
- **同時に `.github/dependabot.yml` に `github-actions` ecosystem (weekly / grouped) を置く**。SHA pin にすると Dependabot の脆弱性アラートが出なくなる (アラートは semver pin にしか出ない) ため、version update と組にして初めて割に合う
- 既存 workflow が tag pin のままなら `pinact run` で一括移行する (GitHub API を叩くので手元の shell で実行)
- pnpm 11.16+ なら `pnpm update --include-github-actions` (fish abbr `pnua`) でも更新できる。常時有効化する `update: githubActions: true` は **この repo の `pnpm-workspace.yaml` にしか置けない** (グローバル設定では無視される)

## プロジェクト固有の注意点

(ここに記載)
