# Setup script for dotnet-api repository
# Verifies and installs required tools: .NET SDK, Docker

param(
    [switch]$InstallMissing = $false
)

$ErrorActionPreference = "Stop"

Write-Host "=== dotnet-api Repository Setup ===" -ForegroundColor Cyan
Write-Host ""

# Check .NET SDK
Write-Host "Checking .NET SDK..." -NoNewline
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    $version = dotnet --version
    Write-Host " ✓ INSTALLED" -ForegroundColor Green
    Write-Host "  Version: $version"
}
else {
    Write-Host " ✗ NOT FOUND" -ForegroundColor Red
    Write-Host "  Download from: https://dotnet.microsoft.com/download"
    if (-not $InstallMissing) {
        exit 1
    }
    else {
        Write-Host "  Attempting install via winget..." -ForegroundColor Yellow
        winget install Microsoft.DotNet.SDK.8
    }
}

Write-Host ""

# Check Docker
Write-Host "Checking Docker..." -NoNewline
if (Get-Command docker -ErrorAction SilentlyContinue) {
    $version = docker --version
    Write-Host " ✓ INSTALLED" -ForegroundColor Green
    Write-Host "  $version"
}
else {
    Write-Host " ✗ NOT FOUND" -ForegroundColor Red
    Write-Host "  Download from: https://www.docker.com/products/docker-desktop"
    if ($InstallMissing) {
        Write-Host "  Attempting install via winget..." -ForegroundColor Yellow
        winget install Docker.DockerDesktop
    }
}

Write-Host ""

# Verify project can restore
Write-Host "Verifying .NET project..." -NoNewline
try {
    & dotnet restore --dry-run | Out-Null
    Write-Host " ✓ OK" -ForegroundColor Green
}
catch {
    Write-Host " ⚠ WARNING" -ForegroundColor Yellow
    Write-Host "  Run 'dotnet restore' to download dependencies"
}

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host "Ready to build and test dotnet-api"
