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

- 依存の追加 (`npm install <pkg>`) や `npx` は hook でブロックされる。必要なときはユーザーに依頼する
- `~/.npmrc` は `ignore-scripts=true`。ネイティブモジュール (esbuild, sharp, prisma 等) が必要な場合はプロジェクトの `.npmrc` で `ignore-scripts=false` を設定する (サプライチェーン経由のビルド時実行を許すため、影響範囲を理解した上で)

## プロジェクト固有の注意点

(ここに記載)
