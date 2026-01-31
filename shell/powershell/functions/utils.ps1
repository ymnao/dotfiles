# Utility Functions for PowerShell
# Common utility commands and helpers

#---------------------------------------------------------------
# Command Utilities
#---------------------------------------------------------------

# Which command (like Unix which)
function which {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command
    )

    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if ($cmd) {
        $cmd.Source
    } else {
        Write-Host "Command not found: $Command" -ForegroundColor Red
    }
}

# Touch command (like Unix touch)
function touch {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (Test-Path $Path) {
        (Get-Item $Path).LastWriteTime = Get-Date
    } else {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }
}

#---------------------------------------------------------------
# System Information
#---------------------------------------------------------------

# Display system information
function sysinfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor
    $mem = Get-CimInstance Win32_ComputerSystem
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"

    Write-Host "`nSystem Information" -ForegroundColor Cyan
    Write-Host "==================" -ForegroundColor Cyan
    Write-Host "OS:        $($os.Caption) $($os.Version)"
    Write-Host "Computer:  $env:COMPUTERNAME"
    Write-Host "User:      $env:USERNAME"
    Write-Host "CPU:       $($cpu.Name)"
    Write-Host "Cores:     $($cpu.NumberOfCores) cores, $($cpu.NumberOfLogicalProcessors) threads"
    Write-Host "RAM:       $([math]::Round($mem.TotalPhysicalMemory / 1GB, 2)) GB"

    Write-Host "`nDisk Usage" -ForegroundColor Cyan
    Write-Host "----------" -ForegroundColor Cyan
    foreach ($d in $disk) {
        $used = $d.Size - $d.FreeSpace
        $percent = [math]::Round(($used / $d.Size) * 100, 1)
        $sizeGB = [math]::Round($d.Size / 1GB, 1)
        $freeGB = [math]::Round($d.FreeSpace / 1GB, 1)
        Write-Host "$($d.DeviceID)  $percent% used  ($freeGB GB free of $sizeGB GB)"
    }
}

# Display uptime
function uptime {
    $os = Get-CimInstance Win32_OperatingSystem
    $uptime = (Get-Date) - $os.LastBootUpTime
    Write-Host "Uptime: $($uptime.Days) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes"
}

#---------------------------------------------------------------
# Environment
#---------------------------------------------------------------

# Reload PowerShell profile
function reload {
    . $PROFILE
    Write-Host "Profile reloaded" -ForegroundColor Green
}

# Show PATH in readable format
function path {
    $env:PATH -split ';' | ForEach-Object { $_ }
}

# Show environment variables
function env {
    Get-ChildItem env: | Format-Table Name, Value -AutoSize
}

# Quick edit profile
function editprofile {
    & $env:EDITOR $PROFILE
}

# Quick edit dotfiles
function dotfiles {
    Set-Location "$env:USERPROFILE\dotfiles"
}

#---------------------------------------------------------------
# Network Utilities
#---------------------------------------------------------------

# Get public IP address
# Note: This makes an external request to api.ipify.org
function pubip {
    Write-Host "Querying external service (api.ipify.org)..." -ForegroundColor DarkGray

    # Enforce TLS 1.2+ and restore original setting after
    $originalProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ip = (Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing -TimeoutSec 5).Content
        Write-Host $ip
    } catch {
        Write-Host "Failed to get public IP" -ForegroundColor Red
        if ($_.Exception.Message) {
            Write-Host "  Details: $($_.Exception.Message)" -ForegroundColor DarkGray
        }
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $originalProtocol
    }
}

# Get local IP address
function localip {
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.InterfaceAlias -notmatch "Loopback" -and $_.IPAddress -notmatch "^169" } |
        Select-Object InterfaceAlias, IPAddress
}

# Flush DNS cache
function flushdns {
    Clear-DnsClientCache
    Write-Host "DNS cache flushed" -ForegroundColor Green
}

#---------------------------------------------------------------
# Process Utilities
#---------------------------------------------------------------

# Kill process by name
function pkill {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    Get-Process -Name "*$Name*" -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Host "Killed processes matching: $Name" -ForegroundColor Green
}

# Find process by name
function pgrep {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    Get-Process -Name "*$Name*" -ErrorAction SilentlyContinue |
        Select-Object Id, ProcessName, CPU, WorkingSet64
}

#---------------------------------------------------------------
# File Utilities
#---------------------------------------------------------------

# Quick file checksum
function md5 {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    (Get-FileHash -Path $Path -Algorithm MD5).Hash.ToLower()
}

function sha256 {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
}

# Extract archives (replacement for 7-zip)
function extract {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [string]$Destination = "."
    )

    if (-not (Test-Path $Path)) {
        Write-Host "File not found: $Path" -ForegroundColor Red
        return
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLower()

    switch ($extension) {
        ".zip" {
            Expand-Archive -Path $Path -DestinationPath $Destination -Force
            Write-Host "Extracted to: $Destination" -ForegroundColor Green
        }
        ".tar" {
            if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
                Write-Host "tar command not found. Requires Windows 10 1803+ or install manually." -ForegroundColor Red
                return
            }
            tar -xf $Path -C $Destination
            Write-Host "Extracted to: $Destination" -ForegroundColor Green
        }
        ".gz" {
            if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
                Write-Host "tar command not found. Requires Windows 10 1803+ or install manually." -ForegroundColor Red
                return
            }
            tar -xzf $Path -C $Destination
            Write-Host "Extracted to: $Destination" -ForegroundColor Green
        }
        ".tgz" {
            if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
                Write-Host "tar command not found. Requires Windows 10 1803+ or install manually." -ForegroundColor Red
                return
            }
            tar -xzf $Path -C $Destination
            Write-Host "Extracted to: $Destination" -ForegroundColor Green
        }
        default {
            Write-Host "Unsupported archive format: $extension" -ForegroundColor Red
            Write-Host "Supported: .zip, .tar, .gz, .tgz" -ForegroundColor Yellow
        }
    }
}

# Create zip archive
function compress {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Source,
        [string]$Destination
    )

    if (-not $Destination) {
        $Destination = "$Source.zip"
    }

    Compress-Archive -Path $Source -DestinationPath $Destination -Force
    Write-Host "Created archive: $Destination" -ForegroundColor Green
}

#---------------------------------------------------------------
# Quick Edit/Open
#---------------------------------------------------------------

# Open file/directory in explorer
function open {
    param(
        [string]$Path = "."
    )
    explorer.exe $Path
}

# Open in VS Code
# Note: If VS Code is installed, 'code' command is already available in PATH
# This function is only needed if you want to ensure VS Code is called
function Open-VSCode {
    param(
        [string]$Path = "."
    )
    $vscode = Get-Command code -CommandType Application -ErrorAction SilentlyContinue
    if ($vscode) {
        & $vscode.Source $Path
    } else {
        Write-Host "VS Code is not installed or not in PATH" -ForegroundColor Red
    }
}
Set-Alias vsc Open-VSCode

#---------------------------------------------------------------
# Development Helpers
#---------------------------------------------------------------

# Quick HTTP server (Python)
function serve {
    param(
        [int]$Port = 8000
    )

    if (Get-Command python -ErrorAction SilentlyContinue) {
        Write-Host "Starting HTTP server on http://localhost:$Port" -ForegroundColor Green
        python -m http.server $Port
    } else {
        Write-Host "Python is not installed" -ForegroundColor Red
    }
}

# JSON pretty print
function json-pp {
    param(
        [Parameter(ValueFromPipeline=$true)]
        [string]$Json
    )
    process {
        $Json | ConvertFrom-Json | ConvertTo-Json -Depth 100
    }
}

#---------------------------------------------------------------
# Clipboard
#---------------------------------------------------------------

# Copy to clipboard
function clip-copy {
    param(
        [Parameter(ValueFromPipeline=$true)]
        [string]$Text
    )
    process {
        $Text | Set-Clipboard
        Write-Host "Copied to clipboard" -ForegroundColor Green
    }
}

# Paste from clipboard
function clip-paste {
    Get-Clipboard
}

# Copy file contents to clipboard
function clip-file {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    Get-Content $Path | Set-Clipboard
    Write-Host "File contents copied to clipboard" -ForegroundColor Green
}
