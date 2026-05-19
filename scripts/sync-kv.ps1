<#
.SYNOPSIS
    Sync KV namespaces from infrastructure/kv/namespaces.json to Cloudflare.
.DESCRIPTION
    Reads KV namespace definitions and creates any missing namespaces via Wrangler.
    If namespaces already exist, prints their IDs so bindings can be kept in sync.
    Requires a Cloudflare API token with Workers KV Storage Edit permission.
.PARAMETER DryRun
    Show what would change without creating namespaces.
#>
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$rootDir = Split-Path $PSScriptRoot -Parent
$kvConfigPath = Join-Path $rootDir 'infrastructure/kv/namespaces.json'

if (-not (Test-Path $kvConfigPath)) {
    throw "KV config not found at $kvConfigPath"
}

$kvConfig = Get-Content $kvConfigPath -Raw | ConvertFrom-Json

Write-Host "Syncing KV namespaces..." -ForegroundColor Cyan
if ($DryRun) { Write-Host "DRY RUN MODE — no changes will be made" -ForegroundColor Yellow }

foreach ($namespace in $kvConfig.namespaces) {
    Write-Host "`nProcessing: $($namespace.binding) -> $($namespace.name)" -ForegroundColor White
    if ($namespace.id) {
        Write-Host "  Namespace ID: $($namespace.id)" -ForegroundColor DarkGray
        Write-Host "  Already declared in config" -ForegroundColor Green
        continue
    }

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would create KV namespace" -ForegroundColor Yellow
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

        Write-Host "  Creating KV namespace via Wrangler..." -ForegroundColor Cyan
        $json = & npx wrangler kv namespace create $namespace.name 2>&1 | Out-String
    }
    finally {
        if ($hadApiToken) { $env:CLOUDFLARE_API_TOKEN = $originalApiToken } else { Remove-Item Env:CLOUDFLARE_API_TOKEN -ErrorAction SilentlyContinue }
        if ($hadAccountId) { $env:CLOUDFLARE_ACCOUNT_ID = $originalAccountId } else { Remove-Item Env:CLOUDFLARE_ACCOUNT_ID -ErrorAction SilentlyContinue }
    }

    Write-Host $json.TrimEnd()

    if ($json -match 'id:\s*([0-9a-f]{32,})') {
        Write-Host "  Created namespace ID: $($matches[1])" -ForegroundColor Green
    } else {
        Write-Host "  Namespace created, but ID could not be parsed from Wrangler output." -ForegroundColor Yellow
    }
}

Write-Host "`nKV sync complete." -ForegroundColor Green