# シェル設定ガイド

このディレクトリには、各プラットフォーム向けのシェル設定が含まれています。

## プラットフォーム別シェル

| プラットフォーム | シェル | 設定ファイル |
|----------------|--------|-------------|
| macOS | Fish | `../fish/config.fish` |
| Linux | Fish | `../fish/config.fish` |
| Windows | PowerShell | `powershell/profile.ps1` |

## Fish vs PowerShell 比較

| 機能 | Fish | PowerShell |
|------|------|------------|
| 自動補完 | ✅ 強力 | ✅ PSReadLine |
| 構文ハイライト | ✅ デフォルト | ✅ PSReadLine |
| 履歴検索 | ✅ Ctrl+R | ✅ 上下矢印 |
| エイリアス | ✅ abbr/function | ✅ Set-Alias/function |
| プラグイン | Fisher | PSGallery |
| スクリプト互換性 | Fish独自 | Windows標準 |

## PowerShell設定の詳細

### ファイル構成

```
shell/powershell/
├── profile.ps1              # メインプロファイル
├── config.local.ps1         # ローカル設定（gitignore）
├── config.local.ps1.template # ローカル設定テンプレート
└── functions/
    ├── git-aliases.ps1      # Gitエイリアス
    ├── navigation.ps1       # ナビゲーション関数
    └── utils.ps1            # ユーティリティ関数
```

### プロファイルの読み込み順序

1. `profile.ps1` がロード
2. 環境変数設定（XDG等）
3. PSReadLine設定
4. `functions/` 内の全 `.ps1` ファイルをロード
5. `config.local.ps1` をロード（存在する場合）

### インストール

```powershell
# シンボリックリンクを作成（install.ps1が自動実行）
.\scripts\link.ps1
```

リンク先: `$PROFILE.CurrentUserAllHosts`

## Gitエイリアス一覧

### 基本操作

| エイリアス | コマンド | 説明 |
|-----------|----------|------|
| `gs` | `git status` | ステータス確認 |
| `ga` | `git add` | ファイルをステージ |
| `gaa` | `git add --all` | 全ファイルをステージ |
| `gc` | `git commit` | コミット |
| `gcm` | `git commit -m` | メッセージ付きコミット |
| `gca` | `git commit --amend` | 直前のコミットを修正 |

### ブランチ操作

| エイリアス | コマンド | 説明 |
|-----------|----------|------|
| `gb` | `git branch` | ブランチ一覧 |
| `gba` | `git branch -a` | 全ブランチ一覧 |
| `gbd` | `git branch -d` | ブランチ削除 |
| `gco` | `git checkout` | チェックアウト |
| `gcob` | `git checkout -b` | 新規ブランチ作成 |
| `gsw` | `git switch` | ブランチ切り替え |
| `gswc` | `git switch -c` | 新規ブランチ作成 |

### リモート操作

| エイリアス | コマンド | 説明 |
|-----------|----------|------|
| `gp` | `git push` | プッシュ |
| `gpf` | `git push --force-with-lease` | 安全な強制プッシュ |
| `gpl` | `git pull` | プル |
| `gf` | `git fetch` | フェッチ |
| `gfa` | `git fetch --all --prune` | 全リモートをフェッチ |

### 差分・ログ

| エイリアス | コマンド | 説明 |
|-----------|----------|------|
| `gd` | `git diff` | 差分表示 |
| `gds` | `git diff --staged` | ステージ済みの差分 |
| `gl` | `git log --oneline` | 簡潔なログ |
| `glo` | `git log --oneline --graph` | グラフ付きログ |
| `glg` | `git log --graph --decorate` | 詳細グラフログ |

### マージ・リベース

| エイリアス | コマンド | 説明 |
|-----------|----------|------|
| `gm` | `git merge` | マージ |
| `grb` | `git rebase` | リベース |
| `grbc` | `git rebase --continue` | リベース続行 |
| `grba` | `git rebase --abort` | リベース中止 |

### スタッシュ

| エイリアス | コマンド | 説明 |
|-----------|----------|------|
| `gst` | `git stash` | スタッシュ |
| `gstp` | `git stash pop` | スタッシュを適用して削除 |
| `gstl` | `git stash list` | スタッシュ一覧 |
| `gsts` | `git stash show -p` | スタッシュの内容表示 |

### その他

| エイリアス | コマンド | 説明 |
|-----------|----------|------|
| `gcp` | `git cherry-pick` | チェリーピック |
| `grh` | `git reset HEAD` | HEADにリセット |
| `grhh` | `git reset HEAD --hard` | ハードリセット |
| `gcl` | `git clone` | クローン |
| `gclean` | `git clean -fd` | 未追跡ファイル削除 |

## ナビゲーション関数一覧

| 関数/エイリアス | 説明 |
|----------------|------|
| `..` | 1つ上のディレクトリへ |
| `...` | 2つ上のディレクトリへ |
| `....` | 3つ上のディレクトリへ |
| `~` | ホームディレクトリへ |
| `ll` | 詳細なファイル一覧 |
| `la` | 隠しファイルを含む一覧 |
| `l` | 簡潔なファイル一覧 |
| `mkcd <dir>` | ディレクトリを作成して移動 |
| `take <dir>` | `mkcd`のエイリアス |

## ユーティリティ関数一覧

| 関数 | 説明 |
|------|------|
| `which <cmd>` | コマンドのパスを表示 |
| `touch <file>` | ファイルを作成/更新 |
| `sysinfo` | システム情報を表示 |
| `reload` | プロファイルを再読み込み |
| `path` | PATH環境変数を見やすく表示 |
| `env` | 環境変数を一覧表示 |

## カスタマイズ方法

### ローカル設定の作成

```powershell
# テンプレートからコピー
cp shell/powershell/config.local.ps1.template shell/powershell/config.local.ps1

# 編集
nvim shell/powershell/config.local.ps1
```

### カスタムエイリアスの追加

`config.local.ps1` に以下を追加:

```powershell
# カスタムエイリアス
function myproject { Set-Location "C:\Projects\MyProject" }
Set-Alias -Name vim -Value nvim
```

### 環境変数の追加

```powershell
# config.local.ps1
$env:MY_VAR = "value"
$env:PATH = "C:\MyTools;$env:PATH"
```

### PSReadLineのカスタマイズ

```powershell
# config.local.ps1
# Viモードに切り替え
Set-PSReadLineOption -EditMode Vi

# カスタムカラー
Set-PSReadLineOption -Colors @{
    Command = 'Blue'
    String = 'DarkYellow'
}
```

## トラブルシューティング

### プロファイルが読み込まれない

```powershell
# プロファイルパスを確認
$PROFILE.CurrentUserAllHosts

# プロファイルが存在するか確認
Test-Path $PROFILE.CurrentUserAllHosts

# シンボリックリンクを再作成
.\scripts\link.ps1 -Force
```

### エイリアスが動作しない

```powershell
# functions/ ディレクトリを確認
Get-ChildItem shell/powershell/functions/

# 個別にロード
. shell/powershell/functions/git-aliases.ps1
```

### 実行ポリシーエラー

```powershell
# 現在のポリシーを確認
Get-ExecutionPolicy

# RemoteSignedに設定
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### PSReadLineがない

```powershell
# インストール
Install-Module PSReadLine -Scope CurrentUser -Force

# バージョン確認
Get-Module PSReadLine -ListAvailable
```

## 参考資料

- [PowerShell公式ドキュメント](https://learn.microsoft.com/ja-jp/powershell/)
- [PSReadLine](https://github.com/PowerShell/PSReadLine)
- [Fish Shell](https://fishshell.com/)
- [Oh My Posh](https://ohmyposh.dev/) - PowerShell用プロンプトカスタマイズ（オプション）
