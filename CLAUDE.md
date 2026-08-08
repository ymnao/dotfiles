# CLAUDE.md

dotfiles リポジトリ。各種開発ツールの設定ファイルを管理し、シンボリックリンクで配置する。

## 目的 (このリポジトリが存在する理由)

**毎日使う shell / エディタ / CLI 環境の摩擦を減らし、新しいマシンで同じ環境を再現できる状態を保つこと。**

skill / hook / テスト / CI は、この目的を安全に達成するための**手段**であって目的ではない。
作業の行き先を判断するときはこの 1 文に照らす（`/pr` の起票ゲートが参照する）。

目的側のタスクは**踏んだその場で issue に落とす**（事前の棚卸しでは見つからないため）。手段側と比率で管理しない（経緯は `.claude/backlog.conf` のコメント）。

## 構造の要点

- 各ディレクトリ（fish/, nvim/, wezterm/ 等）が1ツールの設定に対応
- `scripts/link.sh` でシンボリックリンクを作成
- `agents/AGENTS.md` → `~/.claude/CLAUDE.md` にシンボリックリンク
- `claude/settings.json` → `~/.claude/settings.json` にシンボリックリンク
- `claude/managed-settings.json` は **symlink しない**（managed/policy 設定の正本。user が `sudo cp` で `/Library/Application Support/ClaudeCode/` へ配置する。repo へ symlink すると agent の Edit tool から policy を書き換えられるため意図的に配線しない。手順は [docs/ai-operations.md](docs/ai-operations.md) §10）
- `claude/skills/` → `~/.claude/skills/` にシンボリックリンク
- harness 間で内容が同一のスキルの SKILL.md は `codex/skills/` → `claude/skills/` の repo 内シンボリックリンクで drift を防止（pr / resolve は独立ファイルのまま）
- harness 共通の hook 実装は `agents/hooks/` に正本を置き、`claude/hooks/` と `codex/hooks/` からは相対 symlink で参照する（drift を構造的に防止）。codex 固有 hook（redact-secrets / notify-stop）は `codex/hooks/` に実体のまま置く。同じ理由で **Claude 固有 hook は `claude/hooks/` に実体のまま置く**（guard-sandbox-exclusions は Claude Code の `sandbox.excludedCommands` 専用で、codex には相当機構が無い）
- `claude/agents/` → `~/.claude/agents/` にシンボリックリンク（Claude Code サブエージェント定義）
- `claude/rules/` → `~/.claude/rules/` にシンボリックリンク（path-scoped rules、frontmatter の `paths` glob にマッチしたときだけ lazy load）
- `claude/statusline.sh` → `~/.claude/statusline.sh` にシンボリックリンク（Claude Code の statusline スクリプト）
- `starship/starship.toml` → `~/.config/starship.toml` にシンボリックリンク（Starship プロンプト設定、fish から init される）
- `herdr/config.toml` → `~/.config/herdr/config.toml` にシンボリックリンク（herdr = エージェント用ターミナル multiplexer。**ディレクトリごと symlink しない** — socket が config と同じディレクトリに作られるため）
- `.claude/stop-gate.conf` はリポジトリごとの Stop hook 検証ゲート設定（`claude/hooks/stop-verify-gate.sh` が参照するオプトインファイル）
- `.claude/backlog.conf` はリポジトリごとの backlog 観測設定（`/dev` と `/next` が参照するオプトインファイル。`BACKLOG_CAP` は起票ゲートの煙探知機）
- `tests/` — hook・スクリプトの回帰テスト群（make test で全実行）
- `claude/templates/` — 新規プロジェクト用の CLAUDE.md テンプレート（5 種）
- `.github/scripts/` — CI 専用スクリプトの置き場（workflow から `bash <path>` で起動する。CI 依存のバージョン pin と SHA256 の正本もここ）

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
- `make lint-locale-pin` — LC_ALL pin 忘れの静的リンター（issue #192、warning-only。`make test` からも実行）
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
- sandbox は repo の `.git/config` を lock できないため、config を書く git サブコマンド（`push -u` / `fetch <remote> <branch>:<branch>` / `branch -d` 等）は `fatal: failed to store: 100001` や `error: could not lock config file .git/config` を出しながら**本体の操作には成功する**。`fatal:` を失敗と読んで中断しない。成否はエラー出力ではなく**結果の状態**で確かめる（push / fetch は `git ls-remote` の remote SHA と手元の SHA の一致、削除は `git branch` の出力）。エラー文言の有無を判定に使うのは同じ誤りの繰り返し — 測るのは文字列ではなく ref の値
- **ただし「本体は成功する」は全てのコマンドには当てはまらない。`git checkout -b <branch> origin/<branch>` は upstream 設定の書き込みに失敗すると、ref だけ作って HEAD は元のまま・index と working tree だけ切り替え先のツリーに置き換わる半端な状態を残す**（2026-08-07 に実測。`tests/` が物理的に消えた）。remote 追跡ブランチに移るときは **config を書かない 2 段階**で行う: `git branch --no-track <branch> origin/<branch>` → `git checkout <branch>`。復旧は `git restore --source=HEAD --staged --worktree .`（`reset --hard` は禁止のまま）
- 上の復旧後も、`claude/skills/` など sandbox が削除を拒否するパスの実体ファイルが untracked として残り、以後の `git checkout` / `git merge` が「上書きされる untracked がある」と言って中断することがある。**古い commit のツリーへ checkout する作業自体を避ける**（新しいブランチを main から切って変更を載せ直す方が速い）
- **feature ブランチに `git merge main` する形も、上と同じ「削除を拒否するパス」で中断する**。main 側がそれらを書き換えていると `error: unable to unlink old ...` に続いて `Merge with strategy ort failed.` で止まる。**失敗自体は安全**（working tree 無傷・HEAD 不動で、`checkout -b` のような半端な状態は残らない）。回避は「main 側の変更内容を **file 編集 tool** で working tree に適用 → commit → 再度 merge」（差分が消えれば git はそのファイルを触らない。2026-08-08 実測）
- ツールの未使用判定を shell history 単独で行わない。agent（Claude Code / codex）の Bash 実行は shell history に残らないため、ヒット 0 件は未使用の根拠にならない（`figlet` / `poppler` は zsh / fish とも 0 ヒットだが agent セッションログに実行記録がある）。設定ファイル・state の mtime・repo やエディタ設定からの参照・agent のセッションログも併せて見る
