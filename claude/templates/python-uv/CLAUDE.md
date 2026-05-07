# <プロジェクト名>

<1〜2行の概要>

## 構成

- Python + uv
- パッケージマネージャ: uv (`pyproject.toml` + `uv.lock`)

## よく使うコマンド

| 用途 | コマンド |
|---|---|
| 依存インストール (再現性重視) | `uv sync --frozen` |
| 依存インストール (開発) | `uv sync` |
| 依存追加 | `uv add <pkg>` |
| 依存削除 | `uv remove <pkg>` |
| 依存ツリー確認 | `uv tree` |
| テスト | `uv run pytest` |
| Lint / Format | `uv run ruff check` / `uv run ruff format` |
| 型チェック | `uv run mypy .` |
| スクリプト実行 | `uv run python <script>` |

(プロジェクトに合わせて編集)

## uv 操作の指針

- **依存追加**: `uv add <pkg>` — `pyproject.toml` と `uv.lock` を同時に更新
- **依存削除**: `uv remove <pkg>`
- **同期 (CI / 初回)**: `uv sync --frozen` — `uv.lock` から再現性ある環境を作る
- **同期 (開発)**: `uv sync` — `pyproject.toml` の変更を反映
- **lock 更新**: `uv lock --upgrade-package <pkg>` — 単一パッケージのバージョン更新
- **依存確認**: `uv tree` — 依存関係を可視化
- **`uv.lock` を直接編集しない** — 必ず `uv add` / `uv lock` 経由で更新する

## .python-version と direnv

- `.python-version` で Python バージョンを固定。`uv` は自動でこれを参照する
- direnv 連携時は `.envrc` 例: `source $(uv venv --python "$(cat .python-version)" --quiet && echo .venv/bin/activate)` 等
- `.venv/` は `.gitignore` 対象（コミット禁止）

## pyproject.toml と uv.lock

- `pyproject.toml`: 依存の宣言（範囲指定可、人が編集する）
- `uv.lock`: 依存の固定（具体的バージョン、uv が管理する）
- 両方とも commit する（再現性の担保）

## セキュリティ

- `.env*` は Read/Edit 拒否（settings.json で設定済み）
- `uvx` / `uv tool install` は supply chain リスクあり、プロンプト確認
- `pip install --user` はプロンプト確認（user site-packages を汚染するため）
- `pip install --system` / `uv pip install --system` は禁止（システム Python を汚染するため）
- `uv publish` は禁止
- `.venv/`, `__pycache__/`, `uv.lock` の手動編集は禁止

## 注意点

(プロジェクト固有の注意点をここに)
