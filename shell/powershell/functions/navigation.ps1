# Navigation Functions for PowerShell
# Directory navigation helpers similar to Fish/Zsh

#---------------------------------------------------------------
# Directory Navigation
#---------------------------------------------------------------

# Go up one directory
function .. { Set-Location .. }

# Go up two directories
function ... { Set-Location ..\.. }

# Go up three directories
function .... { Set-Location ..\..\.. }

# Go up four directories
function ..... { Set-Location ..\..\..\.. }

# Go to home directory
function ~ { Set-Location $HOME }

# Go to previous directory
function -- { Set-Location - }

#---------------------------------------------------------------
# Directory Listing
#---------------------------------------------------------------

# Detailed listing (like ls -la)
function ll {
    Get-ChildItem -Force $args | Format-Table Mode, LastWriteTime, Length, Name -AutoSize
}

# Show hidden files too (like ls -la)
function la {
    Get-ChildItem -Force $args
}

# Simple listing (like ls)
function l {
    Get-ChildItem $args
}

# List directories only
function ld {
    Get-ChildItem -Directory $args
}

# List files only
function lf {
    Get-ChildItem -File $args
}

# List with human-readable sizes
function lh {
    Get-ChildItem -Force $args | ForEach-Object {
        $size = if ($_.PSIsContainer) {
            "<DIR>"
        } else {
            switch ($_.Length) {
                { $_ -ge 1GB } { "{0:N2} GB" -f ($_ / 1GB); break }
                { $_ -ge 1MB } { "{0:N2} MB" -f ($_ / 1MB); break }
                { $_ -ge 1KB } { "{0:N2} KB" -f ($_ / 1KB); break }
                default { "$_ B" }
            }
        }
        [PSCustomObject]@{
            Mode = $_.Mode
            LastWriteTime = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
            Size = $size
            Name = $_.Name
        }
    } | Format-Table -AutoSize
}

#---------------------------------------------------------------
# Directory Creation & Navigation
#---------------------------------------------------------------

# Create directory and cd into it
function mkcd {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-Location $Path
}

# Alias for mkcd (common in Zsh)
function take {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    mkcd $Path
}

#---------------------------------------------------------------
# Quick Access Directories
#---------------------------------------------------------------

# Common directories (customize in config.local.ps1)
function dev { Set-Location "$env:USERPROFILE\development" }
function docs { Set-Location "$env:USERPROFILE\Documents" }
function dl { Set-Location "$env:USERPROFILE\Downloads" }
function desk { Set-Location "$env:USERPROFILE\Desktop" }

#---------------------------------------------------------------
# Directory Stack
#---------------------------------------------------------------

# Push current directory and change to new one
function pd {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    Push-Location $Path
}

# Pop directory from stack
function pob {
    Pop-Location
}

# Show directory stack
function dirs {
    Get-Location -Stack
}

#---------------------------------------------------------------
# Find in Directory
#---------------------------------------------------------------

# Find files by name pattern
function ff {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Pattern,
        [string]$Path = "."
    )
    Get-ChildItem -Path $Path -Recurse -Name -Filter "*$Pattern*" -ErrorAction SilentlyContinue
}

# Find directories by name pattern
function fd-dir {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Pattern,
        [string]$Path = "."
    )
    Get-ChildItem -Path $Path -Recurse -Directory -Name -Filter "*$Pattern*" -ErrorAction SilentlyContinue
}

#---------------------------------------------------------------
# Tree View
#---------------------------------------------------------------

# Simple tree view (if tree.exe is not available)
function tree-ps {
    param(
        [string]$Path = ".",
        [int]$Depth = 2
    )

    function Show-Tree {
        param(
            [string]$CurrentPath,
            [int]$CurrentDepth,
            [int]$MaxDepth,
            [string]$Prefix = ""
        )

        if ($CurrentDepth -gt $MaxDepth) { return }

        $items = Get-ChildItem -Path $CurrentPath -ErrorAction SilentlyContinue | Sort-Object { -not $_.PSIsContainer }, Name
        $count = $items.Count
        $index = 0

        foreach ($item in $items) {
            $index++
            $isLast = ($index -eq $count)
            $connector = if ($isLast) { "└── " } else { "├── " }
            $newPrefix = if ($isLast) { "$Prefix    " } else { "$Prefix│   " }

            $color = if ($item.PSIsContainer) { "Cyan" } else { "White" }
            Write-Host "$Prefix$connector" -NoNewline
            Write-Host $item.Name -ForegroundColor $color

            if ($item.PSIsContainer) {
                Show-Tree -CurrentPath $item.FullName -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -Prefix $newPrefix
            }
        }
    }

    $fullPath = Resolve-Path $Path
    Write-Host $fullPath -ForegroundColor Green
    Show-Tree -CurrentPath $fullPath -CurrentDepth 1 -MaxDepth $Depth
}
