# <プロジェクト名>

<1〜2行の概要>

## 構成

- TypeScript + Node.js
- パッケージマネージャ: pnpm

## よく使うコマンド

| 用途 | コマンド |
|---|---|
| 依存インストール (CI / 再現性重視) | `pnpm install --frozen-lockfile` |
| 依存インストール (開発) | `pnpm install` |
| テスト | `pnpm test` |
| ビルド | `pnpm build` |
| 型チェック | `pnpm typecheck` |
| Lint | `pnpm lint` |
| 開発サーバ | `pnpm dev` |

(プロジェクトに合わせて編集)

## pnpm 操作の指針

- **依存追加**: `pnpm add <pkg>` （postinstall は `~/.npmrc` の `ignore-scripts=true` で無効化済み）
- **依存削除**: `pnpm remove <pkg>`
- **強制再インストール**: `pnpm install --force`
- **ストア整理**: `pnpm store prune` — `.pnpm-store/` を直接 `rm -rf` しない（content-addressable 整合性が壊れる）
- **corepack/pnpm バージョン衝突**: `corepack prepare pnpm@<version> --activate`

## ネイティブモジュール（esbuild, sharp, prisma 等）

`ignore-scripts=true` 環境では postinstall ビルドスクリプトが走らない。必要なパッケージは `package.json` の `pnpm.onlyBuiltDependencies` でホワイトリスト化:

```json
{
  "pnpm": {
    "onlyBuiltDependencies": ["esbuild", "@swc/core", "sharp"]
  }
}
```

## セキュリティ

- `.env*` は Read/Edit 拒否（settings.json で設定済み）
- 新しい依存追加 (`pnpm add`) はプロンプト確認
- `pnpm dlx` / `npx` は supply chain リスクあり、プロンプト確認
- `npm publish` / `pnpm publish` は禁止
- `node_modules/` および lockfile (`pnpm-lock.yaml`) の手動編集は禁止

## 注意点

(プロジェクト固有の注意点をここに)
