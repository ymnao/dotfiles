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

## npm 操作の指針

- **依存追加**: `npm install <pkg>` (`--save-dev` で dev 依存)
- **依存削除**: `npm uninstall <pkg>`
- **クリーンインストール**: `npm ci` — `package-lock.json` から再現性ある環境を作る
- **依存ツリー確認**: `npm ls --depth=0`
- **重複解決**: `npm dedupe`
- **`package-lock.json` を直接編集しない** — 必ず `npm install` / `npm update` 経由で更新する

## ネイティブモジュール (esbuild, sharp, prisma 等)

`~/.npmrc` の `ignore-scripts=true` 環境では postinstall ビルドが走らない。必要なパッケージは個別に `--ignore-scripts=false` を付けるか、プロジェクトの `.npmrc` で上書きする:

```
# .npmrc (project local)
ignore-scripts=false
```

ただしプロジェクト `.npmrc` で全許可にするとサプライチェーン経由のビルド時実行を許してしまうため、影響範囲を理解した上で設定すること。

## セキュリティ

- `.env*` は Read/Edit 拒否（settings.json で設定済み）
- 新しい依存追加 (`npm install <pkg>`) はプロンプト確認
- `npx` は supply chain リスクあり、プロンプト確認
- `npm install -g` / `npm i -g` は禁止（system Node を汚染するため）
- `npm publish` は禁止
- `node_modules/` および `package-lock.json` の手動編集は禁止

## 注意点

(プロジェクト固有の注意点をここに)
