# キーボードカスタマイズガイド

このディレクトリには、各プラットフォーム向けのキーボードカスタマイズ設定が含まれています。

## プラットフォーム別ツール

| プラットフォーム | ツール | 設定ファイル |
|----------------|--------|-------------|
| macOS | Karabiner-Elements | `../karabiner/karabiner.json` |
| Windows | AutoHotkey v2 | `autohotkey/*.ahk` |

## Karabiner vs AutoHotkey 比較

| 機能 | Karabiner-Elements | AutoHotkey v2 |
|------|-------------------|---------------|
| キーリマップ | ✅ 強力 | ✅ 強力 |
| IME制御 | ✅ 簡単 | ✅ 可能（要調整） |
| マクロ | ✅ Complex Modifications | ✅ 柔軟なスクリプト |
| GUI設定 | ✅ あり | ⚠️ テキストベース |
| システム統合 | ✅ 深い | ✅ 深い |
| 学習コスト | 低 | 中 |

## Windows: AutoHotkey設定

### ファイル構成

```
keyboard/autohotkey/
├── dotfiles.ahk           # メインスクリプト（モジュール読み込み）
├── ime-toggle.ahk         # IME切り替え（⭐重要）
├── key-remapping.ahk      # HHKB風キーリマップ
└── install-autohotkey.ps1 # AutoHotkey自動インストール
```

### インストール

```powershell
# 自動インストール（install.ps1に含まれる）
.\keyboard\autohotkey\install-autohotkey.ps1

# 手動インストール
winget install --id AutoHotkey.AutoHotkey
```

### 起動

```powershell
# 手動起動
.\keyboard\autohotkey\dotfiles.ahk

# 自動起動設定（link.ps1が設定）
# スタートアップフォルダにショートカットが作成される
```

## IME切り替え機能 ⭐

### 実装内容

macOSのKarabiner-Elements体験をWindowsで再現：

| キー操作 | 動作 | 説明 |
|---------|------|------|
| **CapsLock** | → Ctrl | CapsLockをCtrlとして使用 |
| **Ctrl単体押し** | → IME英数 | Ctrlを押して離すとIMEオフ（半角） |
| **Ctrl + Space** | → IME全角 | IMEオン（ひらがな） |

### 仕組み

```
1. CapsLock → LCtrl に変換
2. LCtrl を押す
3. 他のキーを押さずに LCtrl を離す
4. → 無変換キー (vkF3) を送信 → IMEオフ

または

1. LCtrl + Space を押す
2. → 変換キー (vkF4) を送信 → IMEオン
```

### 設定のカスタマイズ

`ime-toggle.ahk` を編集して調整できます：

```autohotkey
; IMEオフに使うキーを変更
; デフォルト: 無変換キー (vkF3)
; 代替: Escを2回送信
Send "{vkF3}"  ; または Send "{Esc}{Esc}"

; IMEオンに使うキーを変更
; デフォルト: 変換キー (vkF4)
; 代替: ひらがなキー (vkF2)
Send "{vkF4}"  ; または Send "{vkF2}"
```

## キーリマップ一覧

### HHKB風リマップ

| 元のキー | リマップ後 | 説明 |
|---------|----------|------|
| CapsLock | Ctrl | CapsLockをCtrlに |
| Ctrl+[ | Escape | Vim風エスケープ |
| Ctrl+h | Backspace | Vim風バックスペース |

### 追加リマップ（オプション）

`key-remapping.ahk` で以下を有効化できます：

```autohotkey
; Ctrl+j = Enter
^j::Send "{Enter}"

; Ctrl+m = Enter（一部アプリ用）
^m::Send "{Enter}"

; Windows + hjkl = 矢印キー
#h::Send "{Left}"
#j::Send "{Down}"
#k::Send "{Up}"
#l::Send "{Right}"
```

## トラブルシューティング

### AutoHotkeyが起動しない

```powershell
# AutoHotkeyがインストールされているか確認
winget list --id AutoHotkey.AutoHotkey

# 再インストール
winget install --id AutoHotkey.AutoHotkey --force

# 手動起動してエラーを確認
& "$env:USERPROFILE\development\important\dotfiles\keyboard\autohotkey\dotfiles.ahk"
```

### IME切り替えが動作しない

**原因1**: IMEキーコードが異なる

日本語環境によってキーコードが異なる場合があります：

```autohotkey
; Google日本語入力の場合
Send "{vk1Dsc07B}"  ; 無変換
Send "{vk1Csc079}"  ; 変換

; Microsoft IMEの場合
Send "{vkF3}"  ; 無変換
Send "{vkF4}"  ; 変換
```

**原因2**: 管理者権限が必要

一部のアプリ（管理者権限で実行中）では動作しないことがあります：
- AutoHotkeyを管理者として実行
- または対象アプリを通常権限で実行

### CapsLockが元に戻る

**原因**: CapsLockの状態がトグルされている

```autohotkey
; スクリプト起動時にCapsLockをオフに
SetCapsLockState "AlwaysOff"
```

### キーが二重に入力される

**原因**: キーリピートの設定

```autohotkey
; キーリピートを調整
#MaxThreadsPerHotkey 1
```

## カスタマイズ方法

### 新しいホットキーの追加

`key-remapping.ahk` に追加：

```autohotkey
; Ctrl+Shift+C でカレントパスをコピー
^+c:: {
    path := A_WorkingDir
    A_Clipboard := path
    ToolTip "Copied: " path
    SetTimer () => ToolTip(), -2000
}
```

### アプリ固有の設定

```autohotkey
; Chrome専用のホットキー
#HotIf WinActive("ahk_exe chrome.exe")
^t::Send "^+t"  ; Ctrl+T → Ctrl+Shift+T（最後に閉じたタブを開く）
#HotIf
```

### 条件付きリマップ

```autohotkey
; Caps Lockがオフの時のみ
#HotIf not GetKeyState("CapsLock", "T")
CapsLock::LCtrl
#HotIf
```

## macOSとの対応表

### Karabiner → AutoHotkey

| Karabiner設定 | AutoHotkey設定 |
|--------------|----------------|
| `caps_lock` → `left_control` | `CapsLock::LCtrl` |
| `left_control` (alone) → `japanese_eisuu` | `~LCtrl up::Send "{vkF3}"` |
| `left_control + space` → `japanese_kana` | `LCtrl & Space::Send "{vkF4}"` |

### 修飾キー記号

| 記号 | Karabiner | AutoHotkey |
|-----|-----------|------------|
| ⌘ | `command` | N/A (Windows) |
| ⌃ | `control` | `^` |
| ⌥ | `option` | `!` (Alt) |
| ⇧ | `shift` | `+` |
| ⊞ | N/A | `#` (Win) |

## 参考資料

- [AutoHotkey v2 ドキュメント](https://www.autohotkey.com/docs/v2/)
- [Karabiner-Elements](https://karabiner-elements.pqrs.org/)
- [HHKB キー配列](https://happyhackingkb.com/jp/products/)

## 注意事項

### セキュリティ

- AutoHotkeyスクリプトはシステムレベルでキー入力を監視します
- 信頼できるスクリプトのみを実行してください
- このリポジトリのスクリプトはすべて公開・レビュー済みです

### 互換性

- AutoHotkey v2 を使用しています（v1とは構文が異なります）
- Windows 10 1607以降が必要です
- 一部のゲームやセキュリティソフトではブロックされる可能性があります

### パフォーマンス

- AutoHotkeyは常駐プログラムとして動作します
- CPU/メモリ使用量は最小限（通常1%未満）
- システムトレイにアイコンが表示されます
