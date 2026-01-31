# PowerShell Profile for dotfiles
# IMPORTANT: This file must be SYMLINKED (not copied) to $PROFILE.CurrentUserAllHosts
# $PSScriptRoot resolves to the symlink target (dotfiles directory), enabling relative paths
# to the functions/ directory. If copied, relative paths will break.

#---------------------------------------------------------------
# Environment Variables
#---------------------------------------------------------------

# XDG Base Directory specification
$env:XDG_CONFIG_HOME = "$env:USERPROFILE\.config"
$env:XDG_CACHE_HOME = "$env:USERPROFILE\.cache"
$env:XDG_DATA_HOME = "$env:USERPROFILE\.local\share"
$env:XDG_STATE_HOME = "$env:USERPROFILE\.local\state"

# Editor
$env:EDITOR = "nvim"
$env:VISUAL = "nvim"

# Less (pager) settings
$env:LESS = "-R"
$env:LESSCHARSET = "utf-8"

#---------------------------------------------------------------
# PSReadLine Configuration
#---------------------------------------------------------------

if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine

    # Emacs-style key bindings (similar to Bash/Fish)
    Set-PSReadLineOption -EditMode Emacs

    # History settings
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineOption -MaximumHistoryCount 10000

    # Ensure history directory exists
    $historyDir = "$env:XDG_STATE_HOME\powershell"
    if (-not (Test-Path $historyDir)) {
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
    }
    Set-PSReadLineOption -HistorySavePath "$historyDir\history.txt"

    # Predictive IntelliSense (PowerShell 7.2+)
    if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 2) {
        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineOption -PredictionViewStyle ListView
    }

    # Colors
    Set-PSReadLineOption -Colors @{
        Command   = 'Green'
        Parameter = 'Gray'
        String    = 'Yellow'
        Operator  = 'Magenta'
    }

    # Key bindings
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key Ctrl+d -Function DeleteCharOrExit
    Set-PSReadLineKeyHandler -Key Ctrl+w -Function BackwardDeleteWord

    # History search with Up/Down arrows
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
}

#---------------------------------------------------------------
# Load Function Modules
#---------------------------------------------------------------

# Resolve dotfiles directory robustly (handles symlink edge cases)
$dotfilesDir = $PSScriptRoot
if (-not $dotfilesDir) {
    # Fallback: resolve from profile symlink target
    $profileItem = Get-Item -LiteralPath $PROFILE.CurrentUserAllHosts -ErrorAction SilentlyContinue
    if ($profileItem -and $profileItem.Target) {
        $dotfilesDir = Split-Path -LiteralPath $profileItem.Target
    }
}

$functionsDir = Join-Path $dotfilesDir "functions"

if (Test-Path $functionsDir) {
    Get-ChildItem -Path $functionsDir -Filter "*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            . $_.FullName
            Write-Verbose "Loaded module: $($_.Name)"
        } catch {
            Write-Warning "Failed to load module: $($_.Name) - $_"
        }
    }
}

#---------------------------------------------------------------
# Path Configuration
#---------------------------------------------------------------

# Add common tool paths if they exist
$pathsToAdd = @(
    "$env:USERPROFILE\.cargo\bin",           # Rust
    "$env:USERPROFILE\go\bin",                # Go
    "$env:APPDATA\npm"                        # npm global
)

# Find Python Scripts directory (version-agnostic)
$pythonBase = Join-Path $env:LOCALAPPDATA "Programs\Python"
if (Test-Path $pythonBase) {
    $pythonDirs = Get-ChildItem -Path $pythonBase -Directory -Filter "Python3*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    if ($pythonDirs -and $pythonDirs[0]) {
        $pythonScripts = Join-Path $pythonDirs[0].FullName "Scripts"
        if (Test-Path $pythonScripts) {
            $pathsToAdd += $pythonScripts
        }
    }
}

foreach ($path in $pathsToAdd) {
    # Use case-insensitive exact match (Windows paths are case-insensitive)
    $pathList = $env:PATH -split ';'
    if ((Test-Path $path) -and ($pathList -inotcontains $path)) {
        $env:PATH = "$path;$env:PATH"
    }
}

#---------------------------------------------------------------
# Prompt Customization
#---------------------------------------------------------------

function prompt {
    $currentPath = Get-Location
    $homePattern = [regex]::Escape($HOME)
    $shortPath = $currentPath -replace "^$homePattern", "~"

    # Git branch info (if in a git repo)
    $gitBranch = ""
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $branch = git branch --show-current 2>$null
        if ($branch) {
            $gitBranch = " ($branch)"
        }
    }

    # Build prompt
    Write-Host "[" -NoNewline -ForegroundColor DarkGray
    Write-Host $shortPath -NoNewline -ForegroundColor Cyan
    if ($gitBranch) {
        Write-Host $gitBranch -NoNewline -ForegroundColor Yellow
    }
    Write-Host "]" -NoNewline -ForegroundColor DarkGray
    return " $ "
}

#---------------------------------------------------------------
# Completion
#---------------------------------------------------------------

# Git completion (if git is installed)
if (Get-Command git -ErrorAction SilentlyContinue) {
    # Import posh-git if available
    if (Get-Module -ListAvailable -Name posh-git) {
        Import-Module posh-git -ErrorAction SilentlyContinue
    }
}

# dotnet completion
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($commandName, $wordToComplete, $cursorPosition)
        dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

#---------------------------------------------------------------
# Load Local Configuration
#---------------------------------------------------------------

$localConfig = Join-Path $dotfilesDir "config.local.ps1"
if (Test-Path $localConfig) {
    . $localConfig
    Write-Verbose "Loaded local configuration"
}

#---------------------------------------------------------------
# Startup Message
#---------------------------------------------------------------

if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "PowerShell dotfiles loaded" -ForegroundColor Green
    Write-Host "Profile: $PROFILE" -ForegroundColor DarkGray
}
