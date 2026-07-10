# Windows Symbolic Link / Junction Creation Script
# Creates links for dotfiles configuration

#Requires -Version 5.1

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Import platform detection
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$scriptDir\detect-platform.psm1" -Force

# Colors
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Error-Custom { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }
function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Cyan }
function Write-Skip { param($Message) Write-Host "[SKIP] $Message" -ForegroundColor Blue }

# Dotfiles directory
$DOTFILES_DIR = Split-Path -Parent $scriptDir
Write-Info "Dotfiles directory: $DOTFILES_DIR"

# Platform info
$platformInfo = Get-PlatformInfo
$useDeveloperMode = $platformInfo.IsDeveloperModeEnabled

if ($useDeveloperMode) {
    Write-Success "Developer Mode is enabled - will use symbolic links"
} else {
    Write-Warn "Developer Mode is not enabled - will use junctions for directories"
    Write-Info "File links will be skipped (symbolic links require Developer Mode)"
    Write-Info "To enable Developer Mode: Settings > System > For developers > Developer Mode"
}

# Link function for directories
function New-DirectoryLink {
    param(
        [string]$Source,
        [string]$Destination
    )

    # Resolve full paths
    $originalSource = $Source
    $Source = Resolve-Path $Source -ErrorAction SilentlyContinue
    if (-not $Source) {
        Write-Warn "Source directory does not exist: $originalSource"
        return $false
    }

    # Create parent directory if needed
    $parentDir = Split-Path -Parent $Destination
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    # Backup existing destination
    if (Test-Path $Destination) {
        $isLink = $false
        try {
            $item = Get-Item $Destination -ErrorAction Stop
            $isLink = [bool]$item.LinkType
        } catch {
            Write-Warn "Cannot access destination (may be locked): $Destination"
            return $false
        }

        if ($isLink) {
            # Remove existing link
            Remove-Item $Destination -Force
            Write-Info "Removed existing link: $Destination"
        } elseif ($Force) {
            # Backup regular file/directory (avoid overwriting an existing backup)
            $backup = "$Destination.backup"
            if (Test-Path -LiteralPath $backup) {
                $ts = Get-Date -Format "yyyyMMddHHmmss"
                $backup = "$Destination.backup.$ts"
                $i = 1
                while (Test-Path -LiteralPath $backup) {
                    $backup = "$Destination.backup.$ts.$i"
                    $i++
                }
            }
            Move-Item $Destination $backup
            Write-Warn "Backed up existing item: $Destination -> $backup"
        } else {
            Write-Skip "Destination already exists (use -Force to overwrite): $Destination"
            return $false
        }
    }

    # Create link
    try {
        if ($useDeveloperMode) {
            # Use symbolic link
            New-Item -ItemType SymbolicLink -Path $Destination -Target $Source -Force | Out-Null
            Write-Success "Linked (SymbolicLink): $Destination -> $Source"
        } else {
            # Use junction (works without Developer Mode)
            New-Item -ItemType Junction -Path $Destination -Target $Source -Force | Out-Null
            Write-Success "Linked (Junction): $Destination -> $Source"
        }
        return $true
    } catch {
        Write-Error-Custom "Failed to create link: $_"
        return $false
    }
}

# Link function for files
function New-FileLink {
    param(
        [string]$Source,
        [string]$Destination
    )

    # Resolve full paths
    $originalSource = $Source
    $Source = Resolve-Path $Source -ErrorAction SilentlyContinue
    if (-not $Source) {
        Write-Warn "Source file does not exist: $originalSource"
        return $false
    }

    # Create parent directory if needed
    $parentDir = Split-Path -Parent $Destination
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    # Check Developer Mode for file links
    if (-not $useDeveloperMode) {
        Write-Skip "File link requires Developer Mode (skipped): $Destination"
        return $false
    }

    # Backup existing destination
    if (Test-Path $Destination) {
        $isLink = $false
        try {
            $item = Get-Item $Destination -ErrorAction Stop
            $isLink = [bool]$item.LinkType
        } catch {
            Write-Warn "Cannot access destination (may be locked): $Destination"
            return $false
        }

        if ($isLink) {
            # Remove existing link
            Remove-Item $Destination -Force
            Write-Info "Removed existing link: $Destination"
        } elseif ($Force) {
            # Backup regular file (avoid overwriting an existing backup)
            $backup = "$Destination.backup"
            if (Test-Path -LiteralPath $backup) {
                $ts = Get-Date -Format "yyyyMMddHHmmss"
                $backup = "$Destination.backup.$ts"
                $i = 1
                while (Test-Path -LiteralPath $backup) {
                    $backup = "$Destination.backup.$ts.$i"
                    $i++
                }
            }
            Move-Item $Destination $backup
            Write-Warn "Backed up existing file: $Destination -> $backup"
        } else {
            Write-Skip "Destination already exists (use -Force to overwrite): $Destination"
            return $false
        }
    }

    # Create symbolic link
    try {
        New-Item -ItemType SymbolicLink -Path $Destination -Target $Source -Force | Out-Null
        Write-Success "Linked (SymbolicLink): $Destination -> $Source"
        return $true
    } catch {
        Write-Error-Custom "Failed to create file link: $_"
        return $false
    }
}

Write-Info "Creating configuration links..."

# WezTerm
Write-Info "`nLinking WezTerm configuration..."
$weztermSource = Join-Path $DOTFILES_DIR "wezterm"
$weztermDest = Join-Path $env:USERPROFILE ".config\wezterm"
New-DirectoryLink -Source $weztermSource -Destination $weztermDest

# Neovim
Write-Info "`nLinking Neovim configuration..."
$nvimSource = Join-Path $DOTFILES_DIR "nvim"
$nvimDest = Join-Path $env:LOCALAPPDATA "nvim"
New-DirectoryLink -Source $nvimSource -Destination $nvimDest

# Git
Write-Info "`nLinking Git configuration..."
$gitDir = Join-Path $env:USERPROFILE ".config\git"
if (-not (Test-Path $gitDir)) {
    New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
}

$gitConfigSource = Join-Path $DOTFILES_DIR "git\config"
$gitConfigDest = Join-Path $gitDir "config"
New-FileLink -Source $gitConfigSource -Destination $gitConfigDest

$gitIgnoreSource = Join-Path $DOTFILES_DIR "git\ignore"
$gitIgnoreDest = Join-Path $gitDir "ignore"
New-FileLink -Source $gitIgnoreSource -Destination $gitIgnoreDest

# PowerShell Profile
Write-Info "`nLinking PowerShell profile..."
$profileSource = Join-Path $DOTFILES_DIR "shell\powershell\profile.ps1"
$profileDest = $PROFILE.CurrentUserAllHosts

if (Test-Path $profileSource) {
    New-FileLink -Source $profileSource -Destination $profileDest
} else {
    Write-Warn "PowerShell profile source not found: $profileSource"
    Write-Info "Run Phase 3 implementation to create PowerShell configuration"
}

# AutoHotkey (create startup shortcut, not a symbolic link)
Write-Info "`nSetting up AutoHotkey startup..."
$ahkSource = Join-Path $DOTFILES_DIR "keyboard\autohotkey\dotfiles.ahk"
$startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$ahkShortcut = Join-Path $startupFolder "dotfiles-autohotkey.lnk"

if (Test-Path $ahkSource) {
    try {
        $WScriptShell = New-Object -ComObject WScript.Shell
        $shortcut = $WScriptShell.CreateShortcut($ahkShortcut)
        $shortcut.TargetPath = $ahkSource
        $shortcut.WorkingDirectory = Split-Path -Parent $ahkSource
        $shortcut.Description = "Dotfiles AutoHotkey Key Remapping"
        $shortcut.Save()
        Write-Success "Created AutoHotkey startup shortcut: $ahkShortcut"
    } catch {
        Write-Warn "Failed to create AutoHotkey shortcut: $_"
    }
} else {
    Write-Warn "AutoHotkey script not found: $ahkSource"
    Write-Info "Run Phase 4 implementation to create AutoHotkey configuration"
}

# AI Agent guidelines (AGENTS.md → $env:USERPROFILE\.claude\CLAUDE.md)
Write-Info "`nLinking AI Agent guidelines..."
$claudeDir = Join-Path $env:USERPROFILE ".claude"
if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

$agentsMdSource = Join-Path $DOTFILES_DIR "agents\AGENTS.md"
$agentsMdDest = Join-Path $claudeDir "CLAUDE.md"
if (Test-Path $agentsMdSource) {
    New-FileLink -Source $agentsMdSource -Destination $agentsMdDest
} else {
    Write-Warn "AI Agent guidelines file not found: $agentsMdSource"
}

# Claude Code
Write-Info "`nLinking Claude Code configuration..."
$claudeSettingsSource = Join-Path $DOTFILES_DIR "claude\settings.json"
$claudeSettingsDest = Join-Path $claudeDir "settings.json"
New-FileLink -Source $claudeSettingsSource -Destination $claudeSettingsDest

$claudeSkillsSource = Join-Path $DOTFILES_DIR "claude\skills"
$claudeSkillsDest = Join-Path $claudeDir "skills"
New-DirectoryLink -Source $claudeSkillsSource -Destination $claudeSkillsDest

$claudeHooksSource = Join-Path $DOTFILES_DIR "claude\hooks"
$claudeHooksDest = Join-Path $claudeDir "hooks"
if (Test-Path $claudeHooksSource) {
    New-DirectoryLink -Source $claudeHooksSource -Destination $claudeHooksDest
}

$claudeAgentsSource = Join-Path $DOTFILES_DIR "claude\agents"
$claudeAgentsDest = Join-Path $claudeDir "agents"
if (Test-Path $claudeAgentsSource) {
    New-DirectoryLink -Source $claudeAgentsSource -Destination $claudeAgentsDest
}

$claudeRulesSource = Join-Path $DOTFILES_DIR "claude\rules"
$claudeRulesDest = Join-Path $claudeDir "rules"
if (Test-Path $claudeRulesSource) {
    New-DirectoryLink -Source $claudeRulesSource -Destination $claudeRulesDest
}

$claudeStatuslineSource = Join-Path $DOTFILES_DIR "claude\statusline.sh"
$claudeStatuslineDest = Join-Path $claudeDir "statusline.sh"
if (Test-Path $claudeStatuslineSource) {
    New-FileLink -Source $claudeStatuslineSource -Destination $claudeStatuslineDest
}

# Codex CLI
Write-Info "`nLinking Codex CLI configuration..."
$codexSource = Join-Path $DOTFILES_DIR "codex"
if (Test-Path $codexSource) {
    $codexDir = Join-Path $env:USERPROFILE ".codex"
    if (-not (Test-Path $codexDir)) {
        New-Item -ItemType Directory -Path $codexDir -Force | Out-Null
    }

    $codexAgentsSource = Join-Path $codexSource "AGENTS.md"
    $codexAgentsDest = Join-Path $codexDir "AGENTS.md"
    if (Test-Path $codexAgentsSource) {
        New-FileLink -Source $codexAgentsSource -Destination $codexAgentsDest
    }

    $codexConfigSource = Join-Path $codexSource "config.toml"
    $codexConfigDest = Join-Path $codexDir "config.toml"
    if (Test-Path $codexConfigSource) {
        New-FileLink -Source $codexConfigSource -Destination $codexConfigDest
    }

    $codexHooksJsonSource = Join-Path $codexSource "hooks.json"
    $codexHooksJsonDest = Join-Path $codexDir "hooks.json"
    if (Test-Path $codexHooksJsonSource) {
        New-FileLink -Source $codexHooksJsonSource -Destination $codexHooksJsonDest
    }

    $codexHooksSource = Join-Path $codexSource "hooks"
    $codexHooksDest = Join-Path $codexDir "hooks"
    if (Test-Path $codexHooksSource) {
        New-DirectoryLink -Source $codexHooksSource -Destination $codexHooksDest
    }

    # skills は per-skill 個別 symlink にする（Codex CLI が管理する .system/ と共存させるため）
    $codexSkillsSource = Join-Path $codexSource "skills"
    $codexSkillsDest = Join-Path $codexDir "skills"
    if (Test-Path $codexSkillsSource) {
        # 既存の skills ディレクトリ自体が symlink （旧 link.ps1 の挙動）なら通常ディレクトリに戻す
        if ((Test-Path $codexSkillsDest) -and ((Get-Item $codexSkillsDest -Force).LinkType)) {
            Remove-Item $codexSkillsDest -Force
        }
        if (-not (Test-Path $codexSkillsDest)) {
            New-Item -ItemType Directory -Path $codexSkillsDest -Force | Out-Null
        }
        Get-ChildItem -Path $codexSkillsSource -Directory | ForEach-Object {
            $skillDest = Join-Path $codexSkillsDest $_.Name
            New-DirectoryLink -Source $_.FullName -Destination $skillDest
        }
    }
}

Write-Success "`nSymbolic link creation complete!"

if (-not $useDeveloperMode) {
    Write-Warn "`nNote: Developer Mode is not enabled."
    Write-Info "Some file links were skipped. Enable Developer Mode for full functionality:"
    Write-Info "  Settings > System > For developers > Developer Mode"
}
