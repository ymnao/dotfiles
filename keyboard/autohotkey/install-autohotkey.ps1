# AutoHotkey Installation Script
# Installs AutoHotkey v2 and sets up auto-start

#Requires -Version 5.1

$ErrorActionPreference = "Stop"

function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Error-Custom { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }
function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Cyan }

Write-Info "AutoHotkey Installation Script"
Write-Info "=============================="

# Check if AutoHotkey is already installed
$ahkInstalled = $false
try {
    $ahkPath = Get-Command "AutoHotkey64.exe" -ErrorAction SilentlyContinue
    if ($ahkPath) {
        $ahkInstalled = $true
        Write-Info "AutoHotkey is already installed: $($ahkPath.Source)"
    }
} catch {
    # Not found via Get-Command, check common paths
    $commonPaths = @(
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:ProgramFiles\AutoHotkey\AutoHotkey64.exe",
        "${env:ProgramFiles(x86)}\AutoHotkey\v2\AutoHotkey64.exe"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            $ahkInstalled = $true
            Write-Info "AutoHotkey is already installed: $path"
            break
        }
    }
}

# Install AutoHotkey if not present
if (-not $ahkInstalled) {
    Write-Info "Installing AutoHotkey v2..."

    try {
        # Check if winget is available
        $wingetVersion = winget --version
        Write-Info "Using winget: $wingetVersion"

        # Install AutoHotkey
        winget install --id AutoHotkey.AutoHotkey --accept-package-agreements --accept-source-agreements

        Write-Success "AutoHotkey v2 installed successfully!"
    } catch {
        Write-Error-Custom "Failed to install AutoHotkey via winget: $_"
        Write-Info "Please install manually from: https://www.autohotkey.com/"
        exit 1
    }
}

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mainScript = Join-Path $scriptDir "dotfiles.ahk"

if (-not (Test-Path $mainScript)) {
    Write-Error-Custom "Main script not found: $mainScript"
    exit 1
}

# Create startup shortcut
Write-Info "Setting up auto-start..."
$startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$shortcutPath = Join-Path $startupFolder "dotfiles-autohotkey.lnk"

try {
    $WScriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $mainScript
    $shortcut.WorkingDirectory = $scriptDir
    $shortcut.Description = "Dotfiles AutoHotkey Key Remapping"
    $shortcut.IconLocation = "shell32.dll,12"
    $shortcut.Save()

    Write-Success "Startup shortcut created: $shortcutPath"
} catch {
    Write-Warn "Failed to create startup shortcut: $_"
    Write-Info "You can manually create a shortcut to: $mainScript"
}

# Start the script now
Write-Info "Starting AutoHotkey script..."
try {
    Start-Process $mainScript
    Write-Success "AutoHotkey script is now running!"
    Write-Info "Look for the AutoHotkey icon in the system tray."
} catch {
    Write-Warn "Failed to start script: $_"
    Write-Info "Please run manually: $mainScript"
}

Write-Success "`nAutoHotkey setup complete!"
Write-Info "`nFeatures enabled:"
Write-Info "  - CapsLock → Ctrl"
Write-Info "  - Ctrl (alone) → IME Off (英数/半角)"
Write-Info "  - Ctrl + Space → IME On (かな/全角)"
Write-Info "  - Ctrl+[ → Escape"
Write-Info "`nTo customize, edit: $scriptDir"
