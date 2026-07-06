# <プロジェクト名>

<1〜2行の概要>

## 構成

- TypeScript / JavaScript + Node.js
- パッケージマネージャ: yarn

## よく使うコマンド

| 用途 | コマンド |
|---|---|
| 依存インストール (CI / 再現性重視) | `yarn install --immutable` |
| 依存インストール (開発) | `yarn install` |
| テスト | `yarn test` |
| ビルド | `yarn build` |
| 型チェック | `yarn typecheck` |
| Lint | `yarn lint` |
| 開発サーバ | `yarn dev` |

(プロジェクトに合わせて編集)

## 注意

- `~/.npmrc` は `ignore-scripts=true`。ネイティブモジュールが必要な場合はプロジェクト側で上書きする (影響範囲を理解した上で)

## プロジェクト固有の注意点

(ここに記載)
