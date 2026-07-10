# dotfiles の codex/config.toml を $env:USERPROFILE\.codex\config.toml にマージする。
# scripts/codex-merge-config.sh の PowerShell 移植 (ロジック 1:1 対応)。
#
# Codex CLI は ~/.codex/config.toml に以下のセクションを動的に書き込むため、
# symlink にするとリポジトリ内の codex/config.toml が汚染される:
#   [projects.*] / [plugins.*] / [notice.*] / [tui.*] / [hooks.state]
# これらは「マシン固有」かつ「Codex が運用中に書き込む」ため保持し、
# base 設定だけを dotfiles 側から上書きする。
#
# Usage: .\codex-merge-config.ps1 -Source <path> -Destination <path>

#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Source)) {
    throw "Source not found: $Source"
}

# dest から保護対象セクションだけを抽出する (awk 実装と同じ判定):
# 行頭 [ で始まる行ごとに keep を切り替え、keep 中の行を集める。
function Get-PreservedSections {
    param([string]$Path)
    $keep = $false
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-Content -Path $Path -Encoding UTF8)) {
        if ($line -match '^\[') {
            # -cmatch (case-sensitive) で sh の awk ~ と 1:1 対応。
            # TOML section 名は case-sensitive なので [Projects.*] は別テーブル扱い。
            # [projects.*] / [plugins.*] / [notice.*] / [tui.*] / [hooks.state]
            $keep = $line -cmatch '^\[(projects|plugins|notice|tui|hooks\.state)([.\]])'
        }
        if ($keep) { $lines.Add($line) }
    }
    return $lines
}

$preserved = @()
# Get-Item -Force + SilentlyContinue で dangling symlink (reparse point exists
# but target missing) も検出する。Test-Path は dangling symlink に対し $false を
# 返すため、sh の `-L` 独立判定と 1:1 対応にならない。
$item = Get-Item $Destination -Force -ErrorAction SilentlyContinue
$destIsLink = $false
if ($item) {
    $destIsLink = [bool]$item.LinkType
    if (-not $destIsLink) {
        $preserved = Get-PreservedSections -Path $Destination
    }
}

# 既存が symlink (旧 link.ps1 の挙動、dangling 含む) なら削除して実体ファイルに置き換える
if ($destIsLink) {
    Remove-Item $Destination -Force
}

$destDir = Split-Path -Parent $Destination
if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}

# 一時ファイルで構築 → 置換 (書き込み途中の失敗で dest を壊さない)
$tmp = "$Destination.merge.$PID.tmp"
try {
    $content = Get-Content -Path $Source -Raw -Encoding UTF8
    if ($preserved.Count -gt 0) {
        if ($content -notmatch "(`r`n|`n)$") { $content += "`n" }
        $content += "`n" + ($preserved -join "`n") + "`n"
    }
    # BOM なし UTF-8 で書く (TOML パーサ互換のため)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmp, $content, $utf8NoBom)
    Move-Item -Path $tmp -Destination $Destination -Force
} finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
}

Write-Host "[codex-merge-config] $Destination (base: $Source, preserved sections kept)"
