<#
.SYNOPSIS
    Sync R2 buckets from infrastructure/r2/buckets.json to Cloudflare.
.DESCRIPTION
    Reads R2 bucket definitions and creates any missing buckets via Wrangler.
    Existing buckets are listed so the repo stays aligned with Cloudflare.
    Requires a Cloudflare API token with R2 bucket management permissions.
.PARAMETER DryRun
    Show what would change without creating buckets.
#>
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$rootDir = Split-Path $PSScriptRoot -Parent
$r2ConfigPath = Join-Path $rootDir 'infrastructure/r2/buckets.json'

if (-not (Test-Path $r2ConfigPath)) {
    throw "R2 config not found at $r2ConfigPath"
}

$r2Config = Get-Content $r2ConfigPath -Raw | ConvertFrom-Json

Write-Host "Syncing R2 buckets..." -ForegroundColor Cyan
if ($DryRun) { Write-Host "DRY RUN MODE — no changes will be made" -ForegroundColor Yellow }

if (-not $r2Config.buckets -or $r2Config.buckets.Count -eq 0) {
    Write-Host "No R2 buckets declared in config." -ForegroundColor DarkGray
    Write-Host "R2 sync complete." -ForegroundColor Green
    return
}

foreach ($bucket in $r2Config.buckets) {
    Write-Host "`nProcessing: $($bucket.name)" -ForegroundColor White

    if ($bucket.id) {
        Write-Host "  Bucket ID: $($bucket.id)" -ForegroundColor DarkGray
        Write-Host "  Already declared in config" -ForegroundColor Green
        continue
    }

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would create R2 bucket" -ForegroundColor Yellow
        continue
    }

    $apiToken = if ($env:CLOUDFLARE_API_TOKEN) { $env:CLOUDFLARE_API_TOKEN } elseif ($env:CF_API_TOKEN) { $env:CF_API_TOKEN } else { $null }
    $accountId = if ($env:CLOUDFLARE_ACCOUNT_ID) { $env:CLOUDFLARE_ACCOUNT_ID } elseif ($env:CF_ACCOUNT_ID) { $env:CF_ACCOUNT_ID } else { $null }

    if (-not $apiToken) {
        throw "CLOUDFLARE_API_TOKEN/CF_API_TOKEN not set. Add it to .env or environment."
    }
    if (-not $accountId) {
        throw "CLOUDFLARE_ACCOUNT_ID/CF_ACCOUNT_ID not set. Add it to .env or environment."
    }

    $originalApiToken = $env:CLOUDFLARE_API_TOKEN
    $originalAccountId = $env:CLOUDFLARE_ACCOUNT_ID
    $hadApiToken = Test-Path Env:CLOUDFLARE_API_TOKEN
    $hadAccountId = Test-Path Env:CLOUDFLARE_ACCOUNT_ID

    try {
        $env:CLOUDFLARE_API_TOKEN = $apiToken
        $env:CLOUDFLARE_ACCOUNT_ID = $accountId

        Write-Host "  Creating R2 bucket via Wrangler..." -ForegroundColor Cyan
        $output = & npx wrangler r2 bucket create $bucket.name 2>&1 | Out-String
    }
    finally {
        if ($hadApiToken) { $env:CLOUDFLARE_API_TOKEN = $originalApiToken } else { Remove-Item Env:CLOUDFLARE_API_TOKEN -ErrorAction SilentlyContinue }
        if ($hadAccountId) { $env:CLOUDFLARE_ACCOUNT_ID = $originalAccountId } else { Remove-Item Env:CLOUDFLARE_ACCOUNT_ID -ErrorAction SilentlyContinue }
    }

    Write-Host $output.TrimEnd()

    if ($output -match '([0-9a-f]{32,})') {
        Write-Host "  Bucket identifier detected in Wrangler output." -ForegroundColor Green
    } else {
        Write-Host "  Bucket created, but no identifier was parsed from Wrangler output." -ForegroundColor Yellow
    }
}

Write-Host "`nR2 sync complete." -ForegroundColor Green