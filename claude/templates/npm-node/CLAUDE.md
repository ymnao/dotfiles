# <プロジェクト名>

<1〜2行の概要>

## 構成

- TypeScript / JavaScript + Node.js
- パッケージマネージャ: npm

## よく使うコマンド

| 用途 | コマンド |
|---|---|
| 依存インストール (CI / 再現性重視) | `npm ci` |
| 依存インストール (開発) | `npm install` |
| テスト | `npm test` |
| ビルド | `npm run build` |
| 型チェック | `npm run typecheck` |
| Lint | `npm run lint` |
| 開発サーバ | `npm run dev` |

(プロジェクトに合わせて編集)

## 注意

- `~/.npmrc` は `ignore-scripts=true`。ネイティブモジュール (esbuild, sharp, prisma 等) が必要な場合はプロジェクトの `.npmrc` で `ignore-scripts=false` を設定する (サプライチェーン経由のビルド時実行を許すため、影響範囲を理解した上で)

## CI (GitHub Actions)

- workflow の `uses:` は **full commit SHA + `# vN` コメント**で pin する (tag pin にしない)。tag は後から動かせるので、action 側のリポジトリを乗っ取られると指す先が変わる
- **同時に `.github/dependabot.yml` に `github-actions` ecosystem (weekly / grouped) を置く**。SHA pin にすると Dependabot の脆弱性アラートが出なくなる (アラートは semver pin にしか出ない — GitHub docs、2026-09-07 時点)。**version update を置いてもアラート自体は戻らない**ので、週次で上げ続けて古い版に留まらない形で埋める
- 既存 workflow が tag pin のままなら `pinact run` で一括移行する (GitHub API を叩くので手元の shell で実行)

## プロジェクト固有の注意点

(ここに記載)
