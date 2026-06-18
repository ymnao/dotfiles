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

## Phase 0: スマホ → Mac リモート通知 (MVP)

「自宅 Mac で動く Claude Code の通知をスマホで受け取る」最小構成。1 週間運用して価値を検証する。

### 構成

- **Tailscale** — Mac とスマホを同一 tailnet に置き、外部公開せず到達可能にする
- **mosh + tmux** — スマホの SSH クライアントから長時間セッションを安定保持
- **ntfy** — Notification hook → スマホへの push 通知 (パブリック ntfy.sh + ランダム topic を共有秘密として利用)

双方向の Allow/Deny on phone は Phase 0.5 で拡張予定。Phase 0 は通知の受信のみ。

### セットアップ

1. **Brewfile を反映** (tailscale / mosh / ntfy が追加済み)
   ```
   make install
   ```

2. **Tailscale を起動して tailnet に参加**
   ```
   sudo tailscale up
   ```
   スマホ側にも Tailscale アプリを入れて同じアカウントでログイン。

3. **ntfy topic を生成**
   ```
   bash scripts/setup-ntfy-topic.sh
   ```
   `~/.claude/.ntfy-topic` にランダム topic が保存される (chmod 600、git 管理外)。
   表示される手順に従ってスマホの ntfy アプリで topic を購読する。

4. **動作確認** — Mac で Claude Code を起動して承認待ちを発生させる
   - Funk.aiff が鳴る (既存)
   - スマホに ntfy 通知が届く (新規)

### リモート操作

スマホ SSH クライアント (Termius など) から:
```
mosh <mac-tailscale-hostname> -- tmux new -A -s claude
```
切断しても tmux セッションが Mac 側で生き続けるため、再接続で続きから操作できる。
