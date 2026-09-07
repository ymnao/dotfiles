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
- **同時に `.github/dependabot.yml` に `github-actions` ecosystem (weekly / grouped) を置く**。SHA pin にすると Dependabot の脆弱性アラートが出なくなる (アラートは semver pin にしか出ない — GitHub docs、2026-09-07 時点)。**version update を置いてもアラート自体は戻らない**ので、週次で上げ続けて古い版に留まらない形で埋める
- 既存 workflow が tag pin のままなら `pinact run` で一括移行する (GitHub API を叩くので手元の shell で実行)。`-u` で版も上げるときは `--min-age <日数>` を併せて渡し、公開直後の release を掴まないようにする
- 継続更新は Dependabot に任せ、pnpm 11.16+ の `pnpm update --include-github-actions` (fish abbr `pnua`) は **weekly を待たずに手元で上げたいときだけ**使う。npm 依存と lockfile も一緒に動く点に注意 (actions を「足す」フラグ)。常時有効化する `update.githubActions` は **この repo の `pnpm-workspace.yaml` にしか置けない** (グローバル設定では無視される)

## プロジェクト固有の注意点

(ここに記載)
