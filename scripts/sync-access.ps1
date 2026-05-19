<#
.SYNOPSIS
    Sync Access applications from infrastructure/access/ to Cloudflare.
.DESCRIPTION
    Reads Access application definitions and applies them via Cloudflare API.
#>
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$rootDir = Split-Path $PSScriptRoot -Parent
$accessConfigPath = Join-Path $rootDir 'infrastructure/access/applications.json'

if (-not (Test-Path $accessConfigPath)) {
    throw "Access config not found at $accessConfigPath"
}

$accessConfig = Get-Content $accessConfigPath -Raw | ConvertFrom-Json

$accountId = $env:CF_ACCOUNT_ID
if (-not $accountId) {
    throw "CF_ACCOUNT_ID not set. Add it to .env or environment."
}

$apiToken = $env:CF_API_TOKEN
if (-not $apiToken) {
    throw "CF_API_TOKEN not set. Add it to .env or environment."
}

$headers = @{
    'Authorization' = "Bearer $apiToken"
    'Content-Type'  = 'application/json'
}

$baseUrl = "https://api.cloudflare.com/client/v4/accounts/$accountId/access/apps"

Write-Host "Syncing Access applications for account: $accountId" -ForegroundColor Cyan
if ($DryRun) { Write-Host "DRY RUN MODE — no changes will be made" -ForegroundColor Yellow }

# Get existing applications
$existingResponse = Invoke-RestMethod -Uri "$baseUrl?per_page=100" -Headers $headers -Method Get
$existingApps = $existingResponse.result | Group-Object { $_.domain } -AsHashTable -AsString

foreach ($desired in $accessConfig.applications) {
    Write-Host "`nProcessing: $($desired.name) ($($desired.domain))" -ForegroundColor White

    if ($desired.worker_protection) {
        Write-Host "  Protected by worker: $($desired.worker_protection) — skipping Access policy" -ForegroundColor DarkYellow
        continue
    }

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would ensure Access application exists" -ForegroundColor Yellow
        continue
    }

    $appBody = @{
        domain          = $desired.domain
        name            = $desired.name
        type            = $desired.type
        session_duration = $desired.session_duration
    } | ConvertTo-Json

    if ($existingApps.ContainsKey($desired.domain)) {
        $existing = $existingApps[$desired.domain] | Select-Object -First 1
        Write-Host "  Updating existing application (ID: $($existing.id))" -ForegroundColor DarkGray
        Invoke-RestMethod -Uri "$baseUrl/$($existing.id)" -Headers $headers -Method Put -Body $appBody | Out-Null
    } else {
        Write-Host "  Creating new application" -ForegroundColor DarkGray
        Invoke-RestMethod -Uri $baseUrl -Headers $headers -Method Post -Body $appBody | Out-Null
    }
}

Write-Host "`nAccess sync complete." -ForegroundColor Green
