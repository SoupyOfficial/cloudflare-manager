<#
.SYNOPSIS
    Copies production Worker secrets to the test environment.
.DESCRIPTION
    Reads secret names from each production worker, then prompts you to enter
    the value for each one so it can be applied to the corresponding test worker.
    Cloudflare does not expose secret values after they are set, so you must
    re-enter them — they are the same values as production.
.EXAMPLE
    pwsh scripts/copy-secrets-to-test.ps1
#>

$ErrorActionPreference = 'Stop'
$rootDir = Split-Path $PSScriptRoot -Parent

# Map of prod worker dir -> test --env name
$workers = @(
    @{ Dir = 'site-auth'; ProdName = 'plot-generator-site-auth'; TestEnv = 'test' },
    @{ Dir = 'llm-proxy'; ProdName = 'llm-api'; TestEnv = 'test' },
    @{ Dir = 'telemetry'; ProdName = 'plot-generator-telemetry'; TestEnv = 'test' }
)

Write-Host "`nCopying production secrets to test environment" -ForegroundColor Cyan
Write-Host "Cloudflare does not expose secret values — enter the same values you set for prod.`n" -ForegroundColor DarkGray

foreach ($worker in $workers) {
    $workerDir = Join-Path $rootDir "workers/$($worker.Dir)"
    Push-Location $workerDir

    Write-Host "─────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "Worker: $($worker.ProdName)" -ForegroundColor White

    # List secret names from the production worker
    try {
        $secretsJson = & npx wrangler@latest secret list --name $worker.ProdName 2>&1 | Out-String
        $secrets = $secretsJson | ConvertFrom-Json -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  Could not list secrets: $_" -ForegroundColor Yellow
        $secrets = @()
    }

    if (-not $secrets -or $secrets.Count -eq 0) {
        Write-Host "  No secrets found for prod worker — skipping." -ForegroundColor DarkGray
        Pop-Location
        continue
    }

    foreach ($secret in $secrets) {
        $name = $secret.name
        Write-Host "`n  Secret: $name" -ForegroundColor Yellow
        $value = Read-Host -Prompt "  Enter value (same as prod)"
        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Host "  Skipped (empty)." -ForegroundColor DarkGray
            continue
        }

        # Pipe the value via stdin to avoid it appearing in shell history
        $value | & npx wrangler@latest secret put $name --env $worker.TestEnv
    }

    Pop-Location
}

Write-Host "`n✔ Done. Test secrets synced." -ForegroundColor Green
Write-Host "Verify with: npx wrangler secret list --name <worker>-test" -ForegroundColor DarkGray
