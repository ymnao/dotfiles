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

- action の継続更新は Dependabot に任せ、pnpm 11.16+ の `pnpm update --include-github-actions` (fish abbr `pnua`) は **weekly を待たずに手元で上げたいときだけ**使う。npm 依存と lockfile も一緒に動く点に注意 (actions を「足す」フラグ)。常時有効化する `update.githubActions` は **この repo の `pnpm-workspace.yaml` にしか置けない** (グローバル設定では無視される)

## プロジェクト固有の注意点

(ここに記載)
