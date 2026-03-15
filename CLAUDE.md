# CLAUDE.md

dotfiles リポジトリ。各種開発ツールの設定ファイルを管理し、シンボリックリンクで配置する。

## 構造の要点

- 各ディレクトリ（fish/, nvim/, wezterm/ 等）が1ツールの設定に対応
- `scripts/link.sh` でシンボリックリンクを作成
- `agents/AGENTS.md` → `~/.claude/CLAUDE.md` にシンボリックリンク
- `claude/settings.json` → `~/.claude/settings.json` にシンボリックリンク
- `claude/skills/` → `~/.claude/skills/` にシンボリックリンク

## よく使うコマンド

- `make install` — 初回セットアップ（Homebrew + パッケージ + シンボリックリンク）
- `make link` — シンボリックリンクのみ作成
- `make update` — パッケージ更新
- `make brewfile` — Brewfile を現在のインストール状態から更新
- `make lint` — secretlint でシークレット漏洩チェック
- `make clean` — 壊れたシンボリックリンクを削除
- `make test` — 設定ファイルの検証

## セキュリティ

- `~/.config/git/config.local` は個人情報を含むため **絶対にコミットしない**
- `.local`, `.private`, `.env` 系ファイルはすべて .gitignore 済み
- コミット前に `make lint` でチェック

## 変更時の注意

- 新ツール追加時は `scripts/link.sh` にシンボリックリンク定義を追加
- Homebrew パッケージ追加時は `make brewfile` で Brewfile を更新
