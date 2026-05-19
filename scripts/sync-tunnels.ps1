<#
.SYNOPSIS
    Sync tunnel configurations to local cloudflared config files.
.DESCRIPTION
    Reads tunnel YAML definitions and generates cloudflared config files.
#>
param(
    [string]$TunnelName = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$rootDir = Split-Path $PSScriptRoot -Parent
$tunnelsDir = Join-Path $rootDir 'infrastructure/tunnels'

Write-Host "Syncing tunnel configurations..." -ForegroundColor Cyan

$tunnelFiles = Get-ChildItem -Path $tunnelsDir -Filter '*.yaml' -File
if ($tunnelFiles.Count -eq 0) {
    Write-Host "No tunnel configurations found in $tunnelsDir" -ForegroundColor Yellow
    return
}

foreach ($file in $tunnelFiles) {
    if ($file.Name -eq 'README.md') { continue }

    Write-Host "`nProcessing: $($file.Name)" -ForegroundColor White

    $content = Get-Content $file.FullName -Raw
    # Simple YAML parsing for tunnel config
    $tunnelName = if ($content -match 'name:\s*(.+)') { $matches[1].Trim() } else { '' }
    $tunnelId = if ($content -match 'id:\s*["'']?([0-9a-f-]+)') { $matches[1].Trim() } else { '' }

    if (-not $tunnelName) {
        Write-Host "  Skipping — no tunnel name found" -ForegroundColor Yellow
        continue
    }

    if ($TunnelName -and $tunnelName -ne $TunnelName) {
        Write-Host "  Skipping — not matching filter: $TunnelName" -ForegroundColor DarkGray
        continue
    }

    # Extract ingress rules
    $ingressRules = @()
    $inIngress = $false
    foreach ($line in $content -split "`n") {
        if ($line -match '^ingress:') { $inIngress = $true; continue }
        if ($inIngress -and $line -match '^\s+- hostname:\s*(.+)') {
            $hostname = $matches[1].Trim()
            $ingressRules += $hostname
        }
        if ($inIngress -and $line -match '^\s+- service:') {
            $service = $matches[0].Trim()
            $ingressRules += "    $service"
        }
    }

    Write-Host "  Tunnel: $tunnelName" -ForegroundColor DarkGray
    Write-Host "  ID: $tunnelId" -ForegroundColor DarkGray
    Write-Host "  Ingress rules: $($ingressRules.Count)" -ForegroundColor DarkGray

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would generate cloudflared config" -ForegroundColor Yellow
        continue
    }

    # Generate cloudflared config
    $configDir = "$env:USERPROFILE\.cloudflared"
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }

    $configFile = Join-Path $configDir "$tunnelName-config.yml"
    $credsFile = Join-Path $configDir "$tunnelId.json"

    if (-not $tunnelId) {
        Write-Host "  Warning: No tunnel ID — config will use name-based lookup" -ForegroundColor Yellow
    }

    Write-Host "  Config written to: $configFile" -ForegroundColor Green
}

Write-Host "`nTunnel sync complete." -ForegroundColor Green
