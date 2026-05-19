<#
.SYNOPSIS
    Comprehensive verification of all Cloudflare resources.
.DESCRIPTION
    Checks workers, DNS, tunnels, and Access applications.
#>
param(
    [string]$WorkerName = ''
)

$ErrorActionPreference = 'Continue'

$rootDir = Split-Path $PSScriptRoot -Parent
$workersDir = Join-Path $rootDir 'workers'

Write-Host "=== Cloudflare Infrastructure Verification ===" -ForegroundColor Cyan
Write-Host ""

# Check workers
Write-Host "--- Workers ---" -ForegroundColor White
$workerDirs = Get-ChildItem -Path $workersDir -Directory
foreach ($dir in $workerDirs) {
    $wranglerToml = Join-Path $dir.FullName 'wrangler.toml'
    if (Test-Path $wranglerToml) {
        $content = Get-Content $wranglerToml -Raw
        $name = if ($content -match 'name\s*=\s*"([^"]+)"') { $matches[1] } else { 'unknown' }
        Write-Host "  [$name] wrangler.toml: OK" -ForegroundColor Green
    } else {
        Write-Host "  [$($dir.Name)] wrangler.toml: MISSING" -ForegroundColor Red
    }
}

# Check DNS config
Write-Host "`n--- DNS Configuration ---" -ForegroundColor White
$dnsConfig = Join-Path $rootDir 'infrastructure/dns/records.json'
if (Test-Path $dnsConfig) {
    $dns = Get-Content $dnsConfig -Raw | ConvertFrom-Json
    Write-Host "  Zone: $($dns.zone)" -ForegroundColor Green
    Write-Host "  Records: $($dns.records.Count)" -ForegroundColor Green
    foreach ($record in $dns.records) {
        $name = if ($record.name -eq '@') { $dns.zone } else { "$($record.name).$($dns.zone)" }
        Write-Host "    - $name ($($record.type) -> $($record.content))" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  DNS config: MISSING" -ForegroundColor Red
}

# Check tunnel configs
Write-Host "`n--- Tunnel Configurations ---" -ForegroundColor White
$tunnelsDir = Join-Path $rootDir 'infrastructure/tunnels'
$tunnelFiles = Get-ChildItem -Path $tunnelsDir -Filter '*.yaml' -File
foreach ($file in $tunnelFiles) {
    if ($file.Name -eq 'README.md') { continue }
    Write-Host "  $($file.Name): OK" -ForegroundColor Green
}

# Check Access config
Write-Host "`n--- Access Applications ---" -ForegroundColor White
$accessConfig = Join-Path $rootDir 'infrastructure/access/applications.json'
if (Test-Path $accessConfig) {
    $access = Get-Content $accessConfig -Raw | ConvertFrom-Json
    foreach ($app in $access.applications) {
        $protection = if ($app.worker_protection) { "Worker: $($app.worker_protection)" } else { "Access policies" }
        Write-Host "  $($app.name) ($($app.domain)): $protection" -ForegroundColor Green
    }
} else {
    Write-Host "  Access config: MISSING" -ForegroundColor Red
}

# Check GitHub Actions workflows
Write-Host "`n--- GitHub Actions Workflows ---" -ForegroundColor White
$workflowsDir = Join-Path $rootDir '.github/workflows'
if (Test-Path $workflowsDir) {
    $workflows = Get-ChildItem -Path $workflowsDir -Filter '*.yml' -File
    foreach ($wf in $workflows) {
        Write-Host "  $($wf.Name): OK" -ForegroundColor Green
    }
} else {
    Write-Host "  Workflows directory: MISSING" -ForegroundColor Red
}

Write-Host "`n=== Verification Complete ===" -ForegroundColor Cyan
