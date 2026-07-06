# <プロジェクト名>

<1〜2行の概要>

## 構成

- Python + uv
- Python バージョン: `.python-version` を参照

## よく使うコマンド

| 用途 | コマンド |
|---|---|
| 依存インストール (CI / 再現性重視) | `uv sync --frozen` |
| 依存インストール (開発) | `uv sync` |
| テスト | `uv run pytest` |
| Lint / Format | `uv run ruff check .` / `uv run ruff format .` |
| 型チェック | `uv run mypy .` |
| スクリプト実行 | `uv run <script>` |

(プロジェクトに合わせて編集)

## 注意

- 依存の追加 (`uv add`)、`uvx`、`uv tool install`、`uv run --with` は hook でブロックされる。必要なときはユーザーに依頼する

## プロジェクト固有の注意点

(ここに記載)
