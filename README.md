# dotfiles

個人用の開発環境設定ファイル（macOS / Linux / Windows対応）

## セットアップ

### macOS / Linux

```bash
# 開発ディレクトリにリポジトリをクローン
git clone https://github.com/YOUR_USERNAME/dotfiles.git ~/development/important/dotfiles
cd ~/development/important/dotfiles

# 自動セットアップ（Homebrew、パッケージインストール、シンボリックリンク作成）
make install
```

または手動で：

```bash
# シンボリックリンクのみ作成
make link

# パッケージインストール
brew bundle install
```

### Windows

> **推奨**: シンボリックリンク作成には**開発者モード**が必要です。
> 設定 → プライバシーとセキュリティ → 開発者向け → 開発者モード

```powershell
# リポジトリをクローン
git clone https://github.com/YOUR_USERNAME/dotfiles.git $env:USERPROFILE\development\important\dotfiles
cd $env:USERPROFILE\development\important\dotfiles

# 実行ポリシー設定（初回のみ）
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

# 自動セットアップ（Winget、シンボリックリンク、AutoHotkey）
.\scripts\install.ps1

# Scoopも含める場合（CLIツール: lazygit, delta, fzf等）
.\scripts\install.ps1 -InstallScoop
```

または手動で：

```powershell
# シンボリックリンクのみ作成
.\scripts\link.ps1

# パッケージインストール
# packages/winget-packages.txt を参照
```

## 含まれる設定

### 共通（全プラットフォーム）
- **WezTerm** - ターミナルエミュレータ（Kanagawa/OneDarkテーマ、プラットフォーム対応キーバインド）
- **Neovim** - エディタ（Lazy.nvimでプラグイン管理）
- **Git** - バージョン管理（delta diff付き）

### macOS
- **Fish** - シェル
- **Karabiner-Elements** - キーボードカスタマイズ

### Windows
- **PowerShell** - シェル（Fish風エイリアス50以上）
- **AutoHotkey** - キーボードカスタマイズ（IME切り替え、HHKB風キーバインド）

## ディレクトリ構成

```
dotfiles/
├── fish/           # Fish設定（macOS/Linux）
├── git/            # Git設定
├── karabiner/      # Karabiner設定（macOS）
├── nvim/           # Neovim設定
├── wezterm/        # WezTerm設定（プラットフォーム対応）
├── shell/          # PowerShell設定（Windows）
├── keyboard/       # AutoHotkey設定（Windows）
├── packages/       # パッケージ管理（Winget）
├── scripts/        # セットアップスクリプト
├── Brewfile        # Homebrewパッケージリスト
└── Makefile        # タスクランナー
```

## よく使うコマンド

```bash
make help       # ヘルプ表示
make install    # フルインストール
make link       # シンボリックリンク作成
make update     # Homebrewパッケージ更新
make brewfile   # Brewfile更新
```

## ⚠️ セキュリティ注意事項

### 7-Zip / p7zipの使用禁止

**全プラットフォームで7-Zip / p7zipの使用を禁止しています**

**理由**: アーカイブ展開時のリモートコード実行脆弱性が過去に複数報告されています。
最新のセキュリティ情報は公式サイトで確認してください。

**代替手段**:
- **macOS**: 標準の`zip`/`unzip`、または [The Unarchiver](https://theunarchiver.com/)
- **Windows**: 標準の`Compress-Archive`/`Expand-Archive`
- **Linux**: `tar`, `unzip`, `gzip` 等の標準ツール

### 個人情報の設定

Git の個人情報は **別ファイルで管理** してください：

```bash
# テンプレートをコピー
cp git/config.local.template ~/.config/git/config.local

# 自分の情報を記入
nvim ~/.config/git/config.local
```

### 追跡しないファイル

以下は自動的に除外されます（`.gitignore`に記載）：
- `*.local` - 個人設定
- `.env`, `.env.*` - 環境変数
- `.DS_Store` - macOSメタデータ
- `automatic_backups/` - Karabinerバックアップ

## カスタマイズ

マシン固有の設定は `.local` ファイルで：

```bash
~/.config/git/config.local           # Git個人情報
~/.config/fish/config.local.fish     # Fish個人設定
```

これらは自動で読み込まれ、Gitで追跡されません。

## Windows固有の機能

### IME切り替え（AutoHotkey）

macOSのKarabiner-Elements体験をWindowsで再現：
- **CapsLock → Ctrl**: CapsLockをCtrlとして使用
- **Ctrl単体押し → IME英数**: Ctrlを押して離すとIMEオフ
- **Ctrl + Space → IME全角**: IMEオン（ひらがな）

### WezTermキーマップ

| 操作 | macOS | Windows |
|------|-------|---------|
| ペイン水平分割 | CMD+D | CTRL+D |
| ペイン垂直分割 | CMD+SHIFT+D | CTRL+SHIFT+D |
| 新規タブ | CMD+T | CTRL+T |
| ペイン移動 | CMD+h/j/k/l | ALT+h/j/k/l |

### PowerShell Fish風エイリアス

50以上のGitエイリアス：`gs`, `ga`, `gc`, `gp`, `gl`, `gco`, `gb`, `gd`等

詳細: `shell/README.md`

### パッケージ管理（Winget + Scoop）

| 用途 | マネージャー | 例 |
|------|-------------|-----|
| GUIアプリ | Winget | VS Code, WezTerm |
| 言語ランタイム | Winget | Python, Node.js, Go |
| CLI開発ツール | Scoop | lazygit, delta, fzf |

セキュリティ: Scoopは公式バケット（main, extras）のみ使用

詳細: `packages/README.md`

## 参考

- [dotfiles.github.io](https://dotfiles.github.io/)
- [awesome-dotfiles](https://github.com/webpro/awesome-dotfiles)
