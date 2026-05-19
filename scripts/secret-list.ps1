<#
.SYNOPSIS
    List secrets for all workers.
.DESCRIPTION
    Shows which secrets are defined in each worker's wrangler.toml.
#>
param()

$ErrorActionPreference = 'Stop'

$rootDir = Split-Path $PSScriptRoot -Parent
$workersDir = Join-Path $rootDir 'workers'

Write-Host "=== Worker Secrets ===" -ForegroundColor Cyan
Write-Host ""

$workers = Get-ChildItem -Path $workersDir -Directory
foreach ($w in $workers) {
    $wranglerToml = Join-Path $w.FullName 'wrangler.toml'
    if (-not (Test-Path $wranglerToml)) { continue }

    $content = Get-Content $wranglerToml -Raw
    $name = if ($content -match 'name\s*=\s*"([^"]+)"') { $matches[1] } else { $w.Name }

    # Extract secret comments
    $secrets = @()
    foreach ($line in $content -split "`n") {
        if ($line -match '#\s*-?\s*([A-Z_]+)\s*\(set via|#\s*-\s*([A-Z_]+)\s*$') {
            $secret = if ($matches[1]) { $matches[1] } else { $matches[2] }
            if ($secret -and $secret -cmatch '^[A-Z_]+$') {
                $secrets += $secret
            }
        }
    }

    if ($secrets.Count -gt 0) {
        Write-Host "$name:" -ForegroundColor White
        foreach ($s in $secrets) {
            Write-Host "  - $s" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "$name: (no secrets defined)" -ForegroundColor Yellow
    }
    Write-Host ""
}
