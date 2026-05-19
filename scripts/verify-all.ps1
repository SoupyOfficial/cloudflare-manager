<#
.SYNOPSIS
    Comprehensive verification of all Cloudflare resources.
.DESCRIPTION
    Checks workers, DNS, tunnels, Access applications, local Cloudflare env vars,
    and optionally GitHub Actions secrets.
#>
param(
    [string]$WorkerName = '',
    [switch]$CheckGitHubSecrets
)

$ErrorActionPreference = 'Continue'

$rootDir = Split-Path $PSScriptRoot -Parent
$workersDir = Join-Path $rootDir 'workers'
$envFile = Join-Path $rootDir '.env'
$requiredEnvVars = @('CF_API_TOKEN', 'CF_ZONE_ID')

function Get-EnvValueFromFile {
    param([string]$Name)

    if (-not (Test-Path $envFile)) { return $null }

    $line = Get-Content $envFile | Where-Object { $_ -match "^$Name=" } | Select-Object -First 1
    if (-not $line) { return $null }

    return $line.Split('=', 2)[1].Trim()
}

Write-Host "=== Cloudflare Infrastructure Verification ===" -ForegroundColor Cyan
Write-Host ""

# Check local env configuration
Write-Host "--- Local Environment ---" -ForegroundColor White
if (Test-Path $envFile) {
    Write-Host "  .env: FOUND" -ForegroundColor Green
} else {
    Write-Host "  .env: MISSING" -ForegroundColor Red
}

foreach ($name in $requiredEnvVars) {
    $value = [System.Environment]::GetEnvironmentVariable($name, 'Process')
    if (-not $value) {
        $value = Get-EnvValueFromFile -Name $name
    }
    if ($value) {
        Write-Host "  $($name): set" -ForegroundColor Green
    } else {
        Write-Host "  $($name): MISSING" -ForegroundColor Red
    }
}

if ($CheckGitHubSecrets) {
    Write-Host "`n--- GitHub Actions Secrets ---" -ForegroundColor White
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "  gh CLI: MISSING (skipping remote secret check)" -ForegroundColor Yellow
    } else {
        try {
            $secretNames = @()
            foreach ($line in (gh secret list -R SoupyOfficial/cloudflare-manager)) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    $secretNames += ($line -split '\s+')[0]
                }
            }
            foreach ($name in $requiredEnvVars) {
                if ($secretNames -contains $name) {
                    Write-Host "  $($name): present" -ForegroundColor Green
                } else {
                    Write-Host "  $($name): MISSING" -ForegroundColor Red
                }
            }
        } catch {
            Write-Host "  Unable to query GitHub secrets: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

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
