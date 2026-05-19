<#
.SYNOPSIS
    Quick health check of all public endpoints.
.DESCRIPTION
    Tests reachability of all hostnames defined in DNS config.
#>
param(
    [switch]$Detailed
)

$ErrorActionPreference = 'Continue'

$rootDir = Split-Path $PSScriptRoot -Parent
$dnsConfig = Join-Path $rootDir 'infrastructure/dns/records.json'

if (-not (Test-Path $dnsConfig)) {
    throw "DNS config not found at $dnsConfig"
}

$dns = Get-Content $dnsConfig -Raw | ConvertFrom-Json

Write-Host "=== Health Check ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host ""

$results = @()

foreach ($record in $dns.records) {
    $hostname = if ($record.name -eq '@') { $dns.zone } else { "$($record.name).$($dns.zone)" }

    # Skip internal/non-HTTP records
    if ($hostname -match 'cfargotunnel\.com' -or $hostname -match 'workers\.dev') {
        continue
    }

    Write-Host "Checking: https://$hostname" -ForegroundColor White -NoNewline

    try {
        $response = Invoke-WebRequest -Uri "https://$hostname" -Method Get -TimeoutSec 10 -ErrorAction Stop
        $status = $response.StatusCode
        $color = if ($status -ge 200 -and $status -lt 400) { 'Green' } else { 'Yellow' }
        Write-Host " -> $status" -ForegroundColor $color
        $results += [PSCustomObject]@{ Hostname = $hostname; Status = $status; Reachable = $true }
    } catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $status = [int]$_.Exception.Response.StatusCode
            Write-Host " -> $status (auth required)" -ForegroundColor DarkYellow
            $results += [PSCustomObject]@{ Hostname = $hostname; Status = $status; Reachable = $true }
        } else {
            Write-Host " -> UNREACHABLE" -ForegroundColor Red
            $results += [PSCustomObject]@{ Hostname = $hostname; Status = 'N/A'; Reachable = $false }
        }
    }
}

# Also check workers.dev endpoints
Write-Host "`nChecking: https://llm-api.jscampbell21.workers.dev" -ForegroundColor White -NoNewline
try {
    $response = Invoke-WebRequest -Uri "https://llm-api.jscampbell21.workers.dev/" -Method Get -TimeoutSec 10 -ErrorAction Stop
    Write-Host " -> $($response.StatusCode)" -ForegroundColor Green
    $results += [PSCustomObject]@{ Hostname = 'llm-api.jscampbell21.workers.dev'; Status = $response.StatusCode; Reachable = $true }
} catch {
    Write-Host " -> UNREACHABLE" -ForegroundColor Red
    $results += [PSCustomObject]@{ Hostname = 'llm-api.jscampbell21.workers.dev'; Status = 'N/A'; Reachable = $false }
}

# Summary
Write-Host "`n--- Summary ---" -ForegroundColor Cyan
$reachable = ($results | Where-Object { $_.Reachable }).Count
$total = $results.Count
Write-Host "Reachable: $reachable / $total" -ForegroundColor $(if ($reachable -eq $total) { 'Green' } else { 'Yellow' })

if ($Detailed) {
    Write-Host "`nDetailed results:" -ForegroundColor White
    $results | Format-Table -AutoSize
}
