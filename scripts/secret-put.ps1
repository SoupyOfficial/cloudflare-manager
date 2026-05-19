<#
.SYNOPSIS
    Helper to set Worker secrets across all workers.
.DESCRIPTION
    Prompts for secret value and sets it in specified worker(s).
.PARAMETER Worker
    Worker name (or 'all' for all workers).
.PARAMETER SecretName
    Name of the secret to set.
#>
param(
    [string]$Worker = 'all',
    [string]$SecretName = ''
)

$ErrorActionPreference = 'Stop'

$rootDir = Split-Path $PSScriptRoot -Parent
$workersDir = Join-Path $rootDir 'workers'

if (-not $SecretName) {
    $SecretName = Read-Host "Enter secret name"
}

$workers = if ($Worker -eq 'all') {
    Get-ChildItem -Path $workersDir -Directory
} else {
    Get-Item (Join-Path $workersDir $Worker)
}

foreach ($w in $workers) {
    $wranglerToml = Join-Path $w.FullName 'wrangler.toml'
    if (-not (Test-Path $wranglerToml)) { continue }

    $content = Get-Content $wranglerToml -Raw
    $name = if ($content -match 'name\s*=\s*"([^"]+)"') { $matches[1] } else { $w.Name }

    Write-Host "`nSetting $SecretName in worker: $name" -ForegroundColor Cyan
    Write-Host "Working directory: $($w.FullName)" -ForegroundColor DarkGray

    Push-Location $w.FullName
    try {
        npx wrangler secret put $SecretName
    } finally {
        Pop-Location
    }
}

Write-Host "`nSecret setting complete." -ForegroundColor Green
