# ──────────────────────────────────────────────────────────────────
# SilkDiff Installer — Windows (PowerShell)
#
# Usage (from PowerShell):
#   irm https://raw.githubusercontent.com/Jianbe-03/SilkDiff/main/install.ps1 | iex
#
# Or save & run with options:
#   .\install.ps1                      # install latest
#   .\install.ps1 -Version v0.2.0     # specific version
#   .\install.ps1 -Uninstall          # remove
# ──────────────────────────────────────────────────────────────────
#Requires -Version 5.1

param(
    [string]$Version = "latest",
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$Repo       = "Jianbe-03/SilkDiff"
$InstallDir = Join-Path $env:LOCALAPPDATA "SilkDiff"
$BinaryName = "silk.exe"

function Write-SilkInfo  ($msg) { Write-Host "[SilkDiff] $msg" }
function Write-SilkOk    ($msg) { Write-Host "[SilkDiff] ✓ $msg" -ForegroundColor Green }
function Write-SilkErr   ($msg) { Write-Host "[SilkDiff] ✗ $msg" -ForegroundColor Red }
function Write-SilkWarn  ($msg) { Write-Host "[SilkDiff] ⚠ $msg" -ForegroundColor Yellow }

# ── Uninstall ───────────────────────────────────────────────────
if ($Uninstall) {
    Write-Host ""
    Write-Host "  🧵 SilkDiff Uninstaller" -ForegroundColor White
    Write-Host ""

    # Remove install directory
    if (Test-Path $InstallDir) {
        Remove-Item -Recurse -Force $InstallDir
        Write-SilkOk "Removed: $InstallDir"
    }
    else {
        Write-SilkInfo "Not found: $InstallDir (already removed)"
    }

    # Remove from user PATH
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -and $currentPath.Contains($InstallDir)) {
        $newPath = ($currentPath.Split(';') | Where-Object { $_ -ne $InstallDir }) -join ';'
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-SilkOk "Removed from user PATH"
    }

    Write-SilkOk "SilkDiff uninstalled."
    Write-Host ""
    exit 0
}

# ── Install ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "  🧵 SilkDiff Installer" -ForegroundColor White
Write-Host ""

# Only amd64 builds are provided for Windows
$arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq "X64") {
    "amd64"
} elseif ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq "Arm64") {
    "arm64"  # not supported yet, but detect it
} else {
    "unknown"
}

if ($arch -ne "amd64") {
    Write-SilkErr "Only 64-bit Windows (amd64) is supported. Detected: $arch"
    exit 1
}

$platform = "windows-amd64"
Write-SilkInfo "Platform: $platform"

# Build download URL
if ($Version -eq "latest") {
    $url = "https://github.com/$Repo/releases/latest/download/silk-$platform.zip"
}
else {
    $url = "https://github.com/$Repo/releases/download/$Version/silk-$platform.zip"
}
Write-SilkInfo "Downloading: $url"

# Download to temp
$tmpZip = Join-Path ([System.IO.Path]::GetTempPath()) "silk-download.zip"
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing
    Write-SilkOk "Downloaded"
}
catch {
    Write-SilkErr "Download failed: $_"
    exit 1
}

# Extract
Write-SilkInfo "Installing to $InstallDir …"
if (Test-Path $InstallDir) {
    Remove-Item -Recurse -Force $InstallDir
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Expand-Archive -Path $tmpZip -DestinationPath $InstallDir -Force

# The archive contains a silk/ subdirectory — move contents one level up
$innerDir = Join-Path $InstallDir "silk"
if (Test-Path $innerDir) {
    Get-ChildItem -Path $innerDir | Move-Item -Destination $InstallDir -Force
    Remove-Item -Path $innerDir -Force
}

Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
Write-SilkOk "Extracted"

# Add to user PATH
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if (-not $currentPath -or -not $currentPath.Contains($InstallDir)) {
    if ($currentPath) {
        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$InstallDir", "User")
    }
    else {
        [Environment]::SetEnvironmentVariable("PATH", $InstallDir, "User")
    }
    Write-SilkOk "Added $InstallDir to user PATH"
    Write-SilkWarn "Restart your terminal for PATH changes to take effect."
}
else {
    Write-SilkOk "Already on PATH"
}

# Verify
Write-Host ""
$silkExe = Join-Path $InstallDir $BinaryName
if (Test-Path $silkExe) {
    & $silkExe --version
    Write-Host ""
    Write-SilkOk "Installation complete!"
}
else {
    Write-SilkWarn "Binary not found at: $silkExe"
}

Write-Host ""
Write-SilkInfo "Run:  silk --help"
Write-Host ""
