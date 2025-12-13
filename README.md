# dotfiles

個人用の開発環境設定ファイル

## セットアップ

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

## 含まれる設定

- **WezTerm** - ターミナルエミュレータ（Kanagawa/OneDarkテーマ、カスタムキーバインド）
- **Neovim** - エディタ（Lazy.nvimでプラグイン管理）
- **Fish** - シェル
- **Git** - バージョン管理（delta diff付き）
- **Karabiner-Elements** - キーボードカスタマイズ（macOS）

## ディレクトリ構成

```
dotfiles/
├── fish/           # Fish設定
├── git/            # Git設定
├── karabiner/      # Karabiner設定
├── nvim/           # Neovim設定
├── wezterm/        # WezTerm設定
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

## 参考

- [dotfiles.github.io](https://dotfiles.github.io/)
- [awesome-dotfiles](https://github.com/webpro/awesome-dotfiles)
