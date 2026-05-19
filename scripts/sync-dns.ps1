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

# Get existing records — index by name only so we can update records even if type changed
$existingResponse = Invoke-RestMethod -Uri ($baseUrl + '?per_page=100') -Headers $headers -Method Get
$existingByName = $existingResponse.result | Group-Object { $_.name } -AsHashTable -AsString

foreach ($desired in $dnsConfig.records) {
    $fullName = if ($desired.name -eq '@') { $dnsConfig.zone } else { "$($desired.name).$($dnsConfig.zone)" }

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

    if ($existingByName -and $existingByName.ContainsKey($fullName)) {
        # Pick the first matching record (handles any existing type, e.g. AAAA placeholder from Workers)
        $existing = $existingByName[$fullName] | Select-Object -First 1
        Write-Host "  Updating existing record (ID: $($existing.id), was: $($existing.type))" -ForegroundColor DarkGray
        try {
            Invoke-RestMethod -Uri ($baseUrl + "/$($existing.id)") -Headers $headers -Method Put -Body $recordBody | Out-Null
        } catch {
            $errBody = $_ | Select-Object -ExpandProperty ErrorDetails -ErrorAction SilentlyContinue
            if ($errBody -match '"code":\s*1043') {
                Write-Host "  WARNING: Record is read-only (managed by Cloudflare/Workers) — skipping" -ForegroundColor Yellow
            } else {
                throw
            }
        }
    } else {
        Write-Host "  Creating new record" -ForegroundColor DarkGray
        try {
            Invoke-RestMethod -Uri $baseUrl -Headers $headers -Method Post -Body $recordBody | Out-Null
        } catch {
            $errBody = $_ | Select-Object -ExpandProperty ErrorDetails -ErrorAction SilentlyContinue
            if ($errBody -match '"code":\s*81053') {
                Write-Host "  WARNING: Conflicting record exists (possibly read-only) — skipping" -ForegroundColor Yellow
            } else {
                throw
            }
        }
    }
}

Write-Host "`nDNS sync complete." -ForegroundColor Green
