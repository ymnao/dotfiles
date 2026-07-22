# CLAUDE.md

dotfiles リポジトリ。各種開発ツールの設定ファイルを管理し、シンボリックリンクで配置する。

## 構造の要点

- 各ディレクトリ（fish/, nvim/, wezterm/ 等）が1ツールの設定に対応
- `scripts/link.sh` でシンボリックリンクを作成
- `agents/AGENTS.md` → `~/.claude/CLAUDE.md` にシンボリックリンク
- `claude/settings.json` → `~/.claude/settings.json` にシンボリックリンク
- `claude/skills/` → `~/.claude/skills/` にシンボリックリンク
- harness 間で内容が同一のスキルの SKILL.md は `codex/skills/` → `claude/skills/` の repo 内シンボリックリンクで drift を防止（pr / resolve は独立ファイルのまま）
- harness 共通の hook 実装は `agents/hooks/` に正本を置き、`claude/hooks/` と `codex/hooks/` からは相対 symlink で参照する（drift を構造的に防止）。codex 固有 hook（redact-secrets / notify-stop）は `codex/hooks/` に実体のまま置く
- `claude/agents/` → `~/.claude/agents/` にシンボリックリンク（Claude Code サブエージェント定義）
- `claude/rules/` → `~/.claude/rules/` にシンボリックリンク（path-scoped rules、frontmatter の `paths` glob にマッチしたときだけ lazy load）
- `claude/statusline.sh` → `~/.claude/statusline.sh` にシンボリックリンク（Claude Code の statusline スクリプト）
- `starship/starship.toml` → `~/.config/starship.toml` にシンボリックリンク（Starship プロンプト設定、fish から init される）
- `.claude/stop-gate.conf` はリポジトリごとの Stop hook 検証ゲート設定（`claude/hooks/stop-verify-gate.sh` が参照するオプトインファイル）
- `tests/` — hook・スクリプトの回帰テスト群（make test で全実行）
- `claude/templates/` — 新規プロジェクト用の CLAUDE.md テンプレート（5 種）

## よく使うコマンド

- `make install` — 初回セットアップ（Homebrew + パッケージ + シンボリックリンク）
- `make link` — シンボリックリンクのみ作成
- `make update` — パッケージ更新
- `make brewfile-drift` — Brewfile 未追跡のインストール済みパッケージを検出
- `make lint` — secretlint でシークレット漏洩チェック
- `make clean` — 壊れたシンボリックリンクを削除
- `make test` — 設定ファイルの検証（hook 回帰テスト含む）
- `make test-hooks` — hook 回帰テストのみ実行
- `make test-locale-matrix` — `make test` を LC_ALL=C / en_US.UTF-8 / ja_JP.UTF-8 の 3 ロケールで順次実行（issue #181、host に無いロケールは skip）
- `make gate` — Stop hook 用の高速ゲート

AI 運用の方針（モデル使い分け・移行手順・ツール追加の審査基準）は [docs/ai-operations.md](docs/ai-operations.md) を参照

## セキュリティ

- `~/.config/git/config.local` は個人情報を含むため **絶対にコミットしない**
- `.local`, `.private`, `.env` 系ファイルはすべて .gitignore 済み
- コミット前に `make lint` でチェック

## 変更時の注意

- 新ツール追加時は `scripts/link.sh` にシンボリックリンク定義を追加
- Homebrew パッケージ追加・削除時は Brewfile を**手動で編集**する（セクション・コメント・`trusted:` オプションを維持）
- `make brewfile`（`brew bundle dump --force`）は手動編集の構造を全て破壊するため使わない
