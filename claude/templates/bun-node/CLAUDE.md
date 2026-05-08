# <プロジェクト名>

<1〜2行の概要>

## 構成

- TypeScript / JavaScript + Bun (ランタイム + パッケージマネージャ)
- パッケージマネージャ: bun

## よく使うコマンド

| 用途 | コマンド |
|---|---|
| 依存インストール (CI / 再現性重視) | `bun install --frozen-lockfile` |
| 依存インストール (開発) | `bun install` |
| テスト | `bun test` |
| ビルド | `bun run build` |
| 型チェック | `bun run typecheck` |
| Lint | `bun run lint` |
| 開発サーバ | `bun run dev` |
| スクリプト実行 | `bun run <script>` / `bun <file>` |

(プロジェクトに合わせて編集)

## bun 操作の指針

- **依存追加**: `bun add <pkg>` (`--dev` で dev 依存)
- **依存削除**: `bun remove <pkg>`
- **依存更新**: `bun update`
- **lockfile**: `bun.lockb` (binary, 旧) または `bun.lock` (text, Bun 1.2+) — どちらも commit する。手動編集禁止

## bun install の挙動

bun は postinstall を **`trustedDependencies` に列挙されたパッケージのみ** 実行する（npm/yarn と異なるデフォルト）。ネイティブビルドが必要なパッケージは `package.json` で明示する:

```json
{
  "trustedDependencies": ["esbuild", "sharp"]
}
```

`bun pm trust <pkg>` で対話的に追加することも可能。

## ランタイムとしての bun

- `bun <file.ts>` で TypeScript を直接実行可能（トランスパイル不要）
- Node.js との互換性は徐々に向上中だが、Node 専用 native module は動かない場合がある
- `bun:test` は jest 互換 API を提供する組み込みテストランナー

## セキュリティ

- `.env*` は Read/Edit 拒否（settings.json で設定済み）
- 新しい依存追加 (`bun add`) はプロンプト確認
- `bunx` (= `bun x`) / `npx` は supply chain リスクあり、プロンプト確認
- `bun install -g` / `bun add -g` は禁止（system 環境を汚染するため）
- `bun publish` は禁止
- `node_modules/`, `bun.lockb`, `bun.lock` の手動編集は禁止

## 注意点

(プロジェクト固有の注意点をここに)
