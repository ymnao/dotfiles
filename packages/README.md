# パッケージ管理ガイド

このディレクトリには、各プラットフォーム向けのパッケージリストが含まれています。

## プラットフォーム別パッケージマネージャー

### macOS/Linux: Homebrew
- **ファイル**: `../Brewfile`
- **インストール**: `scripts/install.sh` が自動処理
- **手動インストール**: `brew bundle --file=Brewfile`
- **更新**: `brew bundle dump --force --file=Brewfile`

### Windows: Winget + Scoop（併用）

| 用途 | マネージャー | ファイル |
|------|-------------|---------|
| GUIアプリ、言語ランタイム | Winget | `winget-packages.txt` |
| CLI開発ツール | Scoop | `scoop-packages.txt` |

- **インストール（Wingetのみ）**: `scripts/install.ps1`
- **インストール（Scoop含む）**: `scripts/install.ps1 -InstallScoop`
- **Scoopスキップ**: `.\scripts\install.ps1 -SkipScoop`

> **セキュリティ注意**: Scoopのインストールはリモートスクリプトの実行を伴うため、
> デフォルトでは無効です。`-InstallScoop`フラグで明示的にオプトインしてください。

## Windowsパッケージ管理

### Winget

Wingetは公式のWindowsパッケージマネージャーで、Windows 11には標準搭載されており、Windows 10でも利用可能です。

#### インストール

Wingetは Windows 11 に標準搭載されています。Windows 10の場合は以下からインストール：
- Microsoft Store: "アプリ インストーラー"
- 直接ダウンロード: https://github.com/microsoft/winget-cli/releases

#### パッケージのインストール

```powershell
# リストから全パッケージをインストール
Get-Content packages/winget-packages.txt | Where-Object { $_ -notmatch '^#' -and $_ -ne '' } | ForEach-Object {
    winget install --id $_ --accept-package-agreements --accept-source-agreements
}

# 個別パッケージのインストール
winget install --id Git.Git

# パッケージ検索
winget search neovim

# インストール済みパッケージ一覧
winget list
```

#### パッケージの更新

```powershell
# 全パッケージを更新
winget upgrade --all

# 特定パッケージを更新
winget upgrade --id Git.Git
```

#### セキュリティ機能

Wingetには以下のセキュリティ機能があります：
- 全パッケージの自動マルウェアスキャン
- SHA-256ハッシュ検証
- パッケージ提出のモデレーターレビュー
- Microsoft検証済みリポジトリ

`winget-packages.txt` の全パッケージは信頼できるソースから提供されています：
- Microsoft公式（PowerShell、OpenJDK、VS Code）
- 公式プロジェクトリポジトリ（Git、GitHub CLI、Node.js、Go、Rust、Python）
- 信頼できる開発者（Neovim、WezTerm、ripgrep、fd）
- Amazon公式（AWS CLI、SAM CLI）

### Wingetの利点

Wingetを主要パッケージマネージャーとして使用する理由：
- **公式**: Microsoft公式、Windows 11に組み込み
- **安全**: 包括的なセキュリティスキャンと検証
- **広く採用**: 大規模なコミュニティとパッケージエコシステム

## Scoop（CLI開発ツール用）

### Scoopを併用する理由

一部のCLIツールはWingetで利用できないため、Scoopを併用します：

| 観点 | Winget | Scoop |
|------|--------|-------|
| lazygit | ❌ なし | ✅ あり |
| delta (git diff) | ❌ なし | ✅ あり |
| fzf | ❌ なし | ✅ あり |
| 管理者権限 | 多くで必要 | 不要 |
| インストール先 | システム全体 | ユーザー単位 |

### セキュリティポリシー

**公式バケットのみ使用**（サードパーティ禁止）:
- `main` - 公式メインバケット
- `extras` - 公式追加バケット

```powershell
# 現在のバケット確認
scoop bucket list

# 不審なバケットがあれば削除
scoop bucket rm <bucket-name>
```

### Scoopパッケージのインストール

```powershell
# Scoopインストール（手動 - 推奨）
# セキュリティ上、手動インストールを推奨します
irm get.scoop.sh | iex

# または install.ps1 経由（オプトイン）
.\scripts\install.ps1 -InstallScoop

# バケット追加
scoop bucket add main
scoop bucket add extras

# パッケージインストール
scoop install lazygit delta fzf bat

# 一括インストール
Get-Content packages/scoop-packages.txt | Where-Object { $_ -notmatch '^#' -and $_ -ne '' } | ForEach-Object { scoop install $_ }
```

### Scoopの更新

```powershell
# Scoop自体を更新
scoop update

# 全パッケージを更新
scoop update *

# 特定パッケージを更新
scoop update lazygit
```

### Scoopのアンインストール

Scoopはクリーンにアンインストール可能：
```powershell
# 特定パッケージ
scoop uninstall lazygit

# Scoop全体（フォルダ削除で完了）
scoop uninstall scoop
```

## パッケージマッピング: Homebrew → Winget

| ツール | Homebrew | Winget | 備考 |
|------|----------|--------|------|
| Git | `git` | `Git.Git` | コアVCS |
| GitHub CLI | `gh` | `GitHub.cli` | GitHub統合 |
| Neovim | `neovim` | `Neovim.Neovim` | テキストエディタ |
| WezTerm | `wezterm` | `wez.wezterm` | ターミナルエミュレータ |
| PowerShell | N/A | `Microsoft.PowerShell` | シェル（Windows） |
| ripgrep | `ripgrep` | `BurntSushi.ripgrep.MSVC` | 高速検索ツール |
| fd | `fd` | `sharkdp.fd` | 高速find代替 |
| Go | `go` | `GoLang.Go` | Go言語 |
| Python | `python` | `Python.Python.3` | Python言語（最新3.x） |
| Node.js | `nodejs` | `OpenJS.NodeJS` | JavaScriptランタイム |
| Rust | `rust` | `Rustlang.Rustup` | Rust言語 |
| OpenJDK 11 | `openjdk@11` | `Microsoft.OpenJDK.11` | Java 11 |
| OpenJDK 17 | `openjdk@17` | `Microsoft.OpenJDK.17` | Java 17 |
| AWS CLI | `awscli` | `Amazon.AWSCLI` | AWSコマンドライン |
| AWS SAM | `aws-sam-cli` | `Amazon.SAM-CLI` | AWSサーバーレス |
| VS Code | `vscode` | `Microsoft.VisualStudioCode` | コードエディタ |

## 除外パッケージ

### ⚠️ 7-Zip / p7zip - セキュリティリスク

**全プラットフォームで除外（macOS/Windows共通）**:
アーカイブ展開時のリモートコード実行脆弱性が過去に複数報告されています。
最新のセキュリティ情報は公式サイトで確認してください。

**代替手段**: 各OS標準の圧縮ツールを使用してください
```powershell
# Windows: 圧縮
Compress-Archive -Path "folder" -DestinationPath "archive.zip"

# Windows: 解凍
Expand-Archive -Path "archive.zip" -DestinationPath "folder"
```

```bash
# macOS: 圧縮
zip -r archive.zip folder/

# macOS: 解凍
unzip archive.zip
```

### Lazygit
- Wingetで利用不可（Scoop専用パッケージ）
- 必要な場合は手動でインストール: https://github.com/jesseduffield/lazygit/releases

### Tree
- Wingetで利用不可
- PowerShell代替: `tree` コマンドまたはカスタム関数

### C/C++ツールチェーン

**Visual Studio Build Tools** と **LLVM** がwinget-packages.txtに含まれています。

```powershell
# インストール
winget install --id Microsoft.VisualStudio.2022.BuildTools
winget install --id LLVM.LLVM
```

**Build Toolsインストール後の追加設定:**
Visual Studio Installerを開き、以下のワークロードを追加:
- "C++ によるデスクトップ開発" (Desktop development with C++)

**確認コマンド:**
```powershell
cl          # MSVC
clang --version
clangd --version  # Neovim LSP
```

### Watchman
- デフォルトでは含まれていません（React Native専用ツール）
- 必要な場合は個別にインストール: https://facebook.github.io/watchman/

## フォントの手動インストール

WezTermで使用するNerd Fontsと日本語フォントは手動インストールが必要です。

### ダウンロードページを開く（PowerShell）

```powershell
# UDEV Gothic 35（推奨 - 日本語対応プログラミングフォント）
Start-Process "https://github.com/yuru7/udev-gothic/releases"

# JetBrainsMono Nerd Font
Start-Process "https://github.com/ryanoasis/nerd-fonts/releases"

# Cica（日本語対応）
Start-Process "https://github.com/miiton/Cica/releases"
```

### フォント一覧

| フォント | 用途 | ダウンロード |
|---------|------|-------------|
| **UDEV Gothic 35** | 日本語対応、WezTermデフォルト | [GitHub Releases](https://github.com/yuru7/udev-gothic/releases) |
| JetBrainsMono Nerd Font | Nerd Font icons対応 | [GitHub Releases](https://github.com/ryanoasis/nerd-fonts/releases) |
| Cica | 日本語対応 | [GitHub Releases](https://github.com/miiton/Cica/releases) |
| Cascadia Code | Windows標準（フォールバック） | Windows 11標準搭載 |

### インストール手順

1. 上記リンクからZIPファイルをダウンロード
2. ZIPを展開（右クリック → すべて展開）
3. すべての `.ttf` または `.otf` ファイルを選択
4. 右クリック → **"すべてのユーザーに対してインストール"**
5. WezTermを再起動（`Ctrl+Shift+R` でリロード、または再起動）

### WezTermでフォントが見つからない警告が出る場合

```
Unable to load a font specified by your font=wezterm.font('UDEV Gothic 35'...
```

この警告は、指定したフォントがインストールされていない場合に表示されます。
WezTermはフォールバック（Cascadia Code、Consolas）を使用して動作しますが、
上記の手順でフォントをインストールすると警告が消えます。

## トラブルシューティング

### Wingetが見つからない

```powershell
# wingetがインストールされているか確認
winget --version

# インストールされていない場合、Microsoft Storeから「アプリ インストーラー」をインストール
# または https://github.com/microsoft/winget-cli/releases からダウンロード
```

### パッケージのインストールに失敗する

```powershell
# wingetソースを更新
winget source update

# 詳細出力でインストールを試す
winget install --id Git.Git --verbose

# wingetログを確認
Get-Content "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_*\LocalState\DiagOutputDir\*.log" | Select-Object -Last 50
```

### 権限エラー

一部のパッケージは管理者権限が必要です。PowerShellを管理者として実行してください：
```powershell
# PowerShellを右クリック → "管理者として実行"
# その後、インストールスクリプトを実行
.\scripts\install.ps1
```

## 参考資料

- [Wingetドキュメント](https://learn.microsoft.com/ja-jp/windows/package-manager/winget/)
- [Wingetパッケージリポジトリ](https://github.com/microsoft/winget-pkgs)
- [Homebrewドキュメント](https://brew.sh/ja/)
