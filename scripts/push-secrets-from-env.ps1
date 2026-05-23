<#
.SYNOPSIS
    Push Worker secrets from .env to Cloudflare via wrangler secret bulk.
.DESCRIPTION
    Reads secret values from .env and bulk-uploads them to each worker.
    Skips any key whose value is blank in .env.
.PARAMETER Env
    Target Wrangler environment. Defaults to "test". Use "production" for prod.
.PARAMETER DryRun
    Print what would be set without uploading anything.
.EXAMPLE
    pwsh scripts/push-secrets-from-env.ps1
    pwsh scripts/push-secrets-from-env.ps1 -Env production
    pwsh scripts/push-secrets-from-env.ps1 -DryRun
#>
param(
    [string]$Env = 'test',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$rootDir = Split-Path $PSScriptRoot -Parent
$envFile = Join-Path $rootDir '.env'

if (-not (Test-Path $envFile)) {
    throw ".env not found at $envFile. Copy .env.example and fill in values."
}

# Parse .env into a hashtable (skip comments and blank lines)
$envVars = @{}
Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#') -and $line -match '^([^=]+)=(.*)$') {
        $envVars[$matches[1].Trim()] = $matches[2].Trim()
    }
}

# Map: worker dir -> (worker name, secret keys that belong to it)
$workers = @(
    @{
        Dir     = 'site-auth'
        Name    = if ($Env -eq 'test') { 'plot-generator-site-auth-test' } else { 'plot-generator-site-auth' }
        Secrets = @('BASIC_AUTH_USERNAME', 'BASIC_AUTH_PASSWORD', 'OPENCODE_UPSTREAM_URL')
    },
    @{
        Dir     = 'llm-proxy'
        Name    = if ($Env -eq 'test') { 'llm-api-test' } else { 'llm-api' }
        Secrets = @('LLM_HOST_CLIENT_ID', 'LLM_HOST_CLIENT_SECRET', 'OPENAI_API_KEY', 'CLAUDE_API_KEY')
    },
    @{
        Dir     = 'telemetry'
        Name    = if ($Env -eq 'test') { 'plot-generator-telemetry-test' } else { 'plot-generator-telemetry' }
        Secrets = @('TURSO_URL', 'TURSO_AUTH_TOKEN', 'TELEMETRY_TOKEN')
    }
)

if ($DryRun) { Write-Host "DRY RUN — no secrets will be uploaded`n" -ForegroundColor Yellow }
Write-Host "Target environment: $Env`n" -ForegroundColor Cyan

foreach ($worker in $workers) {
    $workerDir = Join-Path $rootDir "workers/$($worker.Dir)"
    Write-Host "── $($worker.Name) ──" -ForegroundColor White

    # Build JSON payload from .env values
    $payload = @{}
    foreach ($key in $worker.Secrets) {
        $val = $envVars[$key]
        if ($val) {
            $payload[$key] = $val
            Write-Host "  ${key}: set" -ForegroundColor Green
        }
        else {
            Write-Host "  ${key}: skipped (blank in .env)" -ForegroundColor DarkGray
        }
    }

    if ($payload.Count -eq 0) {
        Write-Host "  Nothing to upload — all keys blank.`n" -ForegroundColor Yellow
        continue
    }

    if ($DryRun) { Write-Host ""; continue }

    # Write temp JSON, bulk-upload, delete temp file
    $tmpJson = Join-Path ([System.IO.Path]::GetTempPath()) "wrangler-secrets-$($worker.Dir).json"
    try {
        $payload | ConvertTo-Json | Set-Content $tmpJson -Encoding UTF8
        Push-Location $workerDir
        & npx wrangler@latest secret bulk $tmpJson --env $Env
        Pop-Location
    }
    finally {
        Remove-Item $tmpJson -ErrorAction SilentlyContinue
    }
    Write-Host ""
}

Write-Host "Done." -ForegroundColor Green
