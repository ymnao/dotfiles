# Windows Installation Script for dotfiles
# Installs Winget packages, Scoop packages, and creates symbolic links/junctions
#
# Package Strategy:
# - Winget: GUI apps, Microsoft-verified packages, language runtimes
# - Scoop: CLI dev tools (lazygit, delta, fzf, etc.)

#Requires -Version 5.1

param(
    [switch]$SkipPackages,
    [switch]$SkipScoop,
    [switch]$SkipLinks,
    [switch]$Force,
    [switch]$InstallScoop  # Opt-in: explicitly request Scoop installation
)

$ErrorActionPreference = "Stop"

# Import platform detection
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$scriptDir\detect-platform.ps1" -Force

# Colors
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Error-Custom { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }
function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Cyan }

# Dotfiles directory
$DOTFILES_DIR = Split-Path -Parent $scriptDir
Write-Info "Dotfiles directory: $DOTFILES_DIR"

# Platform check
Write-Info "Checking platform requirements..."
$platformInfo = Show-PlatformInfo

if (-not (Test-WindowsVersion)) {
    Write-Error-Custom "Windows version check failed. Aborting installation."
    exit 1
}

if (-not (Test-PowerShellVersion)) {
    Write-Error-Custom "PowerShell version check failed. Aborting installation."
    exit 1
}

# Check for Administrator privileges
if (-not $platformInfo.IsAdmin) {
    Write-Warn "Not running as Administrator. Some installations may require elevation."
    Write-Info "To run as Administrator: Right-click PowerShell → Run as Administrator"
}

# Winget installation
if (-not $SkipPackages) {
    Write-Info "Checking Winget installation..."

    try {
        $wingetVersion = winget --version
        Write-Success "Winget is installed: $wingetVersion"
    } catch {
        Write-Error-Custom "Winget is not installed."
        Write-Info "Please install 'App Installer' from Microsoft Store or download from:"
        Write-Info "https://github.com/microsoft/winget-cli/releases"
        exit 1
    }

    # Install packages
    $packagesFile = Join-Path $DOTFILES_DIR "packages\winget-packages.txt"
    if (Test-Path $packagesFile) {
        Write-Info "Installing packages from $packagesFile..."

        $packages = Get-Content $packagesFile | Where-Object {
            $_ -notmatch '^\s*#' -and $_ -ne ''
        }

        $totalPackages = $packages.Count
        $currentPackage = 0

        foreach ($package in $packages) {
            $currentPackage++
            Write-Info "[$currentPackage/$totalPackages] Installing $package..."

            $output = winget install --id $package --accept-package-agreements --accept-source-agreements --silent 2>&1
            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0) {
                Write-Success "Installed $package"
            } else {
                Write-Warn "Failed to install $package (exit code: $exitCode)"
                $outputText = $output | Out-String

                # Provide specific guidance based on error type
                if ($outputText -match 'administrator|elevation|access denied') {
                    Write-Info "  -> Try running PowerShell as Administrator"
                } elseif ($outputText -match 'No package found|No applicable') {
                    Write-Info "  -> Package ID may be incorrect. Search with: winget search $package"
                } elseif ($outputText -match 'network|internet|0x80072') {
                    Write-Info "  -> Check your internet connection"
                } else {
                    Write-Info "  -> Manual install: winget install --id $package"
                }
            }
        }

        Write-Success "Winget package installation complete!"
    } else {
        Write-Warn "Package list not found: $packagesFile"
    }
} else {
    Write-Info "Skipping Winget package installation (--SkipPackages)"
}

# Scoop installation (CLI dev tools)
# SECURITY: Scoop installation requires downloading and executing a remote script.
# This is disabled by default due to supply-chain risks. Use -InstallScoop to opt-in.
if (-not $SkipPackages -and -not $SkipScoop) {
    Write-Info "`n=========================================="
    Write-Info "Scoop (CLI development tools)"
    Write-Info "==========================================`n"

    # Check if Scoop is already installed
    $scoopInstalled = $false
    try {
        $scoopVersion = scoop --version 2>$null
        if ($scoopVersion) {
            $scoopInstalled = $true
            Write-Success "Scoop is already installed"
        }
    } catch {
        # Scoop not found
    }

    # Install Scoop only if explicitly requested (-InstallScoop flag)
    if (-not $scoopInstalled) {
        if ($InstallScoop) {
            Write-Info "Installing Scoop (opt-in via -InstallScoop flag)..."
            Write-Info "Scoop installs to ~/scoop (no admin required)"

            try {
                # Download Scoop installer to temp file
                # SECURITY TRADE-OFF EXPLANATION:
                # - Scoop is not available via winget or other verified package managers
                # - The installer hash changes with each Scoop release (no stable hash to pin)
                # - Scoop does not publish signed releases or official hash manifests
                # - Therefore, programmatic integrity verification is not feasible
                #
                # Mitigations in place:
                # - Opt-in required (-InstallScoop flag)
                # - TLS 1.2+ enforced
                # - SHA256 displayed for manual verification
                # - User confirmation before execution
                # - Option to inspect script before running

                $scoopInstaller = Join-Path $env:TEMP "scoop-install.ps1"
                Write-Info "Downloading Scoop installer from https://get.scoop.sh ..."

                # Enforce TLS 1.2+ to prevent downgrade attacks
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

                Invoke-WebRequest -Uri "https://get.scoop.sh" -OutFile $scoopInstaller -UseBasicParsing

                # Show hash for manual verification
                $hash = (Get-FileHash $scoopInstaller -Algorithm SHA256).Hash
                Write-Host ""
                Write-Warn "=== Security Notice ==="
                Write-Info "Installer SHA256: $hash"
                Write-Info "Verify at: https://github.com/ScoopInstaller/Install"
                Write-Host ""

                if (-not $Force) {
                    Write-Host "Options:" -ForegroundColor Cyan
                    Write-Host "  [Y] Yes, run the installer"
                    Write-Host "  [I] Inspect the script first"
                    Write-Host "  [N] Cancel"
                    $choice = Read-Host "Your choice"

                    if ($choice.ToUpper() -eq 'I') {
                        Start-Process notepad $scoopInstaller -Wait
                        $choice = Read-Host "Run installer? (y/N)"
                    }

                    if ($choice.ToUpper() -ne 'Y') {
                        Write-Info "Installation cancelled."
                        Remove-Item $scoopInstaller -Force -ErrorAction SilentlyContinue
                        throw "User cancelled Scoop installation"
                    }
                }

                & $scoopInstaller
                Write-Success "Scoop installed successfully!"
                $scoopInstalled = $true
                Remove-Item $scoopInstaller -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Warn "Failed to install Scoop: $_"
                Write-Info "Manual installation: https://scoop.sh"
            }
        } else {
            # Default: Skip Scoop installation with guidance
            Write-Warn "Scoop is not installed."
            Write-Info "Scoop provides CLI tools: lazygit, delta, fzf, bat, etc."
            Write-Host ""
            Write-Info "To install Scoop (accepts supply-chain risk):"
            Write-Info "  Option 1: Re-run with -InstallScoop flag"
            Write-Info "    .\scripts\install.ps1 -InstallScoop"
            Write-Host ""
            Write-Info "  Option 2: Install manually (recommended for security):"
            Write-Info "    irm get.scoop.sh | iex"
            Write-Host ""
            Write-Info "Skipping Scoop packages for now."
        }
    }

    # Install Scoop packages
    if ($scoopInstalled) {
        # Security: Check for unauthorized buckets
        Write-Info "Checking Scoop buckets for security..."
        $allowedBuckets = @("main", "extras")

        # Robust parsing: handle both object and string output formats
        $bucketOutput = scoop bucket list 2>$null
        $currentBuckets = @()
        if ($bucketOutput) {
            # Try object output first (with Name property)
            $currentBuckets = $bucketOutput | ForEach-Object {
                if ($_ -is [PSCustomObject] -and $_.Name) {
                    $_.Name.Trim()
                } elseif ($_ -is [string] -and $_.Trim()) {
                    # Parse text: first whitespace-separated token is bucket name
                    (($_ -split '\s+')[0]).Trim()
                }
            } | Where-Object { $_ -and $_ -ne "" }
        }

        # Check for unauthorized buckets
        $unauthorizedBuckets = @()
        foreach ($bucket in $currentBuckets) {
            if ($bucket -and $bucket -notin $allowedBuckets) {
                $unauthorizedBuckets += $bucket
            }
        }

        if ($unauthorizedBuckets.Count -gt 0) {
            Write-Warn "Found unauthorized Scoop buckets: $($unauthorizedBuckets -join ', ')"
            Write-Info "Allowed buckets: $($allowedBuckets -join ', ')"

            if ($Force) {
                Write-Info "Force flag specified - removing unauthorized buckets..."
                foreach ($bucket in $unauthorizedBuckets) {
                    Write-Warn "Removing: $bucket"
                    scoop bucket rm $bucket 2>$null
                }
            } else {
                Write-Warn "These buckets may contain unverified packages."
                $confirm = Read-Host "Remove unauthorized buckets? (y/N)"
                if ($confirm -eq 'y') {
                    foreach ($bucket in $unauthorizedBuckets) {
                        Write-Warn "Removing: $bucket"
                        scoop bucket rm $bucket 2>$null
                    }
                } else {
                    Write-Info "Keeping existing buckets. Proceed with caution."
                }
            }
        }

        # Add official buckets only (security)
        Write-Info "Adding official Scoop buckets..."
        scoop bucket add main 2>$null
        scoop bucket add extras 2>$null

        # Security: List current buckets
        Write-Info "Current Scoop buckets (official only):"
        scoop bucket list

        # Install packages
        $scoopPackagesFile = Join-Path $DOTFILES_DIR "packages\scoop-packages.txt"
        if (Test-Path $scoopPackagesFile) {
            Write-Info "Installing Scoop packages from $scoopPackagesFile..."

            $scoopPackages = Get-Content $scoopPackagesFile | Where-Object {
                $_ -notmatch '^\s*#' -and $_ -ne ''
            }

            $totalScoopPackages = $scoopPackages.Count
            $currentScoopPackage = 0

            foreach ($package in $scoopPackages) {
                $currentScoopPackage++
                Write-Info "[$currentScoopPackage/$totalScoopPackages] Installing $package..."

                try {
                    scoop install $package
                    Write-Success "Installed $package"
                } catch {
                    Write-Warn "Failed to install $package : $_"
                }
            }

            Write-Success "Scoop package installation complete!"
        } else {
            Write-Warn "Scoop package list not found: $scoopPackagesFile"
        }
    }
} else {
    if ($SkipScoop) {
        Write-Info "Skipping Scoop installation (--SkipScoop)"
    }
}

# Create symbolic links
if (-not $SkipLinks) {
    Write-Info "Creating symbolic links..."
    & "$scriptDir\link.ps1" -Force:$Force
} else {
    Write-Info "Skipping symbolic link creation (--SkipLinks)"
}

# Git config setup
Write-Info "Setting up Git configuration..."
$gitConfigDir = Join-Path $env:USERPROFILE ".config\git"
$gitConfigLocal = Join-Path $gitConfigDir "config.local"
$gitConfigTemplate = Join-Path $DOTFILES_DIR "git\config.local.windows.template"

if (-not (Test-Path $gitConfigLocal)) {
    if (Test-Path $gitConfigTemplate) {
        Write-Info "Creating Git config.local from Windows template..."
        Copy-Item $gitConfigTemplate $gitConfigLocal
        Write-Warn "Please edit $gitConfigLocal and add your personal information:"
        Write-Info "  - user.name"
        Write-Info "  - user.email"
    } else {
        # Fallback to generic template
        $gitConfigGenericTemplate = Join-Path $DOTFILES_DIR "git\config.local.template"
        if (Test-Path $gitConfigGenericTemplate) {
            Write-Info "Creating Git config.local from generic template..."
            Copy-Item $gitConfigGenericTemplate $gitConfigLocal
            Write-Warn "Please edit $gitConfigLocal and add your personal information:"
            Write-Info "  - user.name"
            Write-Info "  - user.email"
        }
    }
} else {
    Write-Info "Git config.local already exists"
}

# PowerShell profile setup
Write-Info "Setting up PowerShell profile..."
$profileTemplate = Join-Path $DOTFILES_DIR "shell\powershell\config.local.ps1.template"
$profileLocal = Join-Path $DOTFILES_DIR "shell\powershell\config.local.ps1"

if (-not (Test-Path $profileLocal) -and (Test-Path $profileTemplate)) {
    Write-Info "Creating PowerShell config.local.ps1 from template..."
    Copy-Item $profileTemplate $profileLocal
    Write-Info "You can customize $profileLocal for machine-specific settings"
}

# AutoHotkey setup
Write-Info "Checking AutoHotkey installation..."
$ahkScript = Join-Path $DOTFILES_DIR "keyboard\autohotkey\install-autohotkey.ps1"
if (Test-Path $ahkScript) {
    Write-Info "Running AutoHotkey installation script..."
    & $ahkScript
} else {
    Write-Warn "AutoHotkey installation script not found: $ahkScript"
    Write-Info "You can manually install AutoHotkey v2 from: https://www.autohotkey.com/"
}

Write-Success "`nInstallation complete!"
Write-Info "`nNext steps:"
Write-Info "  1. Edit Git config: $gitConfigLocal"
Write-Info "  2. Restart PowerShell to load the new profile"
Write-Info "  3. Restart WezTerm to apply new configuration"
Write-Info "  4. Check AutoHotkey is running (system tray icon)"
Write-Info "  5. Install fonts manually if needed (see packages/README.md)"

if (-not $platformInfo.IsDeveloperModeEnabled) {
    Write-Warn "`nDeveloper Mode is not enabled. Symbolic links may not work properly."
    Write-Info "To enable: Settings > Privacy & Security > For developers > Developer Mode"
}
