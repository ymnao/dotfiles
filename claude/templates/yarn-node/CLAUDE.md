# <プロジェクト名>

<1〜2行の概要>

## 構成

- TypeScript / JavaScript + Node.js
- パッケージマネージャ: yarn (classic 1.x / berry 2+ 両対応)

## よく使うコマンド

| 用途 | classic (1.x) | berry (2+) |
|---|---|---|
| 依存インストール (CI / 再現性重視) | `yarn install --frozen-lockfile` | `yarn install --immutable` |
| 依存インストール (開発) | `yarn install` | `yarn install` |
| テスト | `yarn test` | `yarn test` |
| ビルド | `yarn build` | `yarn build` |
| 型チェック | `yarn typecheck` | `yarn typecheck` |
| Lint | `yarn lint` | `yarn lint` |
| 開発サーバ | `yarn dev` | `yarn dev` |

(プロジェクトに合わせて編集)

## yarn 操作の指針

- **依存追加**: `yarn add <pkg>` (`--dev` で dev 依存)
- **依存削除**: `yarn remove <pkg>`
- **依存ツリー確認**: `yarn list --depth=0` (classic) / `yarn info` (berry)
- **`yarn.lock` を直接編集しない** — 必ず `yarn add` / `yarn install` 経由で更新する

## classic と berry の違い

- **classic (1.x)**: 従来の `node_modules` ベース。`.yarnrc` 設定。
- **berry (2+)**: `.yarnrc.yml` 設定。デフォルトで Plug'n'Play (PnP) モード — `node_modules` が無く、`.pnp.cjs` / `.pnp.loader.mjs` が依存解決を担う。
  - PnP モードではエディタ統合に sdk 設定が必要 (`yarn dlx @yarnpkg/sdks vscode` 等)
  - `nodeLinker: node-modules` を `.yarnrc.yml` で指定すれば従来式に戻せる
  - `.yarn/cache/` は zip 圧縮された依存ファイル — 手動編集禁止

`.yarnrc.yml` の有無で判別できる。berry プロジェクトでは `yarn` コマンドが `.yarn/releases/` 配下のバイナリにディスパッチされる点に注意。

## セキュリティ

- `.env*` は Read/Edit 拒否（settings.json で設定済み）
- 新しい依存追加 (`yarn add`) はプロンプト確認
- `yarn dlx` (berry) / `npx` は supply chain リスクあり、プロンプト確認
- `yarn global add` (classic) は禁止（system Node を汚染するため）
- `yarn publish` / `yarn npm publish` (berry) は禁止
- `node_modules/`, `.yarn/cache/`, `.pnp.cjs`, `yarn.lock` の手動編集は禁止

## 注意点

(プロジェクト固有の注意点をここに)
