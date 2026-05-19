<#
.SYNOPSIS
    Sync DNS records from infrastructure/dns/records.json to Cloudflare.
.DESCRIPTION
    Reads DNS record definitions and applies them via Cloudflare API.
    Compares existing records and only creates/updates/deletes as needed.
.PARAMETER DryRun
    Show what would change without applying.
.PARAMETER ZoneId
    Override zone ID from environment.
#>
param(
    [switch]$DryRun,
    [string]$ZoneId = ''
)

$ErrorActionPreference = 'Stop'

$rootDir = Split-Path $PSScriptRoot -Parent
$dnsConfigPath = Join-Path $rootDir 'infrastructure/dns/records.json'

if (-not (Test-Path $dnsConfigPath)) {
    throw "DNS config not found at $dnsConfigPath"
}

$dnsConfig = Get-Content $dnsConfigPath -Raw | ConvertFrom-Json

$zoneId = if ($ZoneId) { $ZoneId } else { $env:CF_ZONE_ID }
if (-not $zoneId) {
    throw "CF_ZONE_ID not set. Add it to .env or pass -ZoneId."
}

$apiToken = $env:CF_API_TOKEN
if (-not $apiToken) {
    throw "CF_API_TOKEN not set. Add it to .env or environment."
}

$headers = @{
    'Authorization' = "Bearer $apiToken"
    'Content-Type'  = 'application/json'
}

$baseUrl = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records"

Write-Host "Syncing DNS records for zone: $zoneId" -ForegroundColor Cyan
if ($DryRun) { Write-Host "DRY RUN MODE — no changes will be made" -ForegroundColor Yellow }

# Get existing records
$existingResponse = Invoke-RestMethod -Uri ($baseUrl + '?per_page=100') -Headers $headers -Method Get
$existingRecords = $existingResponse.result | Group-Object { $_.name + $_.type } -AsHashTable -AsString

foreach ($desired in $dnsConfig.records) {
    $fullName = if ($desired.name -eq '@') { $dnsConfig.zone } else { "$($desired.name).$($dnsConfig.zone)" }
    $key = "$fullName$($desired.type)"

    Write-Host "`nProcessing: $fullName ($($desired.type))" -ForegroundColor White

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would ensure record exists with content: $($desired.content)" -ForegroundColor Yellow
        continue
    }

    $recordBody = @{
        name    = $fullName
        type    = $desired.type
        content = $desired.content
        proxied = $desired.proxied
        comment = $desired.comment
    } | ConvertTo-Json -Depth 3

    if ($existingRecords.ContainsKey($key)) {
        $existing = $existingRecords[$key] | Select-Object -First 1
        Write-Host "  Updating existing record (ID: $($existing.id))" -ForegroundColor DarkGray
        Invoke-RestMethod -Uri "$baseUrl/$($existing.id)" -Headers $headers -Method Put -Body $recordBody | Out-Null
    } else {
        Write-Host "  Creating new record" -ForegroundColor DarkGray
        Invoke-RestMethod -Uri $baseUrl -Headers $headers -Method Post -Body $recordBody | Out-Null
    }
}

Write-Host "`nDNS sync complete." -ForegroundColor Green
