<#
.SYNOPSIS
    Sync WAF custom rules from infrastructure/firewall/rules.json to Cloudflare.
.DESCRIPTION
    Reads WAF rule definitions and applies them via Cloudflare Rulesets API.
    Uses the http_request_firewall_custom phase for zone-level WAF rules.
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
$rulesConfigPath = Join-Path $rootDir 'infrastructure/firewall/rules.json'

if (-not (Test-Path $rulesConfigPath)) {
    throw "Firewall rules config not found at $rulesConfigPath"
}

$rulesConfig = Get-Content $rulesConfigPath -Raw | ConvertFrom-Json

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

$baseUrl = "https://api.cloudflare.com/client/v4/zones/$zoneId/rulesets"
$phase = "http_request_firewall_custom"

Write-Host "Syncing WAF custom rules for zone: $zoneId" -ForegroundColor Cyan
if ($DryRun) { Write-Host "DRY RUN MODE — no changes will be made" -ForegroundColor Yellow }

# Check if a custom ruleset already exists for this phase
Write-Host "`nChecking for existing $phase ruleset..." -ForegroundColor DarkGray
$existingResponse = $null
try {
    $existingResponse = Invoke-RestMethod -Uri "$baseUrl/phases/$phase/entrypoint" -Headers $headers -Method Get
}
catch {
    # Cloudflare returns an error when no entrypoint ruleset exists for the phase yet.
    # Treat that as "no existing ruleset" so first-time deploy can create one.
    $existingResponse = $null
}

$existingRulesetId = $null
$existingRules = @()

if ($existingResponse.success -and $existingResponse.result) {
    $existingRulesetId = $existingResponse.result.id
    $existingRules = $existingResponse.result.rules
    Write-Host "  Found existing ruleset: $($existingResponse.result.name) (ID: $existingRulesetId)" -ForegroundColor DarkGray
    Write-Host "  Current rule count: $($existingRules.Count)" -ForegroundColor DarkGray
} else {
    Write-Host "  No existing ruleset found for phase $phase" -ForegroundColor DarkGray
}

# Build desired rules from config
$desiredRules = @()
$priority = 1

foreach ($rule in $rulesConfig.rules) {
    if (-not $rule.enabled) {
        Write-Host "  Skipping disabled rule: $($rule.name)" -ForegroundColor DarkYellow
        continue
    }

    $desiredRule = @{
        action = $rule.action
        expression = $rule.expression
        description = if ($rule.description) { $rule.description } else { $rule.name }
    }

    if ($rule.action_parameters) {
        $actionParams = @{}
        if ($rule.action_parameters.rules) {
            $phases = @()
            $products = @()
            foreach ($r in $rule.action_parameters.rules) {
                switch ($r) {
                    # Skip Super Bot Fight Mode phase (Bot Fight Mode itself cannot be skipped via custom rules)
                    'bot_management' {
                        $phases += 'http_request_sbfm'
                    }
                    # Skip legacy Security Level product
                    'security_level' {
                        $products += 'securityLevel'
                    }
                    default {
                        # Allow explicit product API values in config (for example: zoneLockdown, uaBlock, bic)
                        $products += $r
                    }
                }
            }

            if ($phases.Count -gt 0) { $actionParams.phases = @($phases | Select-Object -Unique) }
            if ($products.Count -gt 0) { $actionParams.products = @($products | Select-Object -Unique) }
        }
        $desiredRule.action_parameters = $actionParams
    }

    $desiredRules += $desiredRule
}

Write-Host "`nDesired rules to deploy: $($desiredRules.Count)" -ForegroundColor White
foreach ($r in $desiredRules) {
    Write-Host "  - $($r.description) [$($r.action)]" -ForegroundColor DarkGray
}

if ($DryRun) {
    Write-Host "`n[DRY RUN] Would create/update ruleset with $($desiredRules.Count) rules" -ForegroundColor Yellow
    exit 0
}

# Build the ruleset body
$rulesetBody = @{
    name = "Custom WAF Rules - madebysoupy.dev"
    kind = "zone"
    phase = $phase
    rules = $desiredRules
} | ConvertTo-Json -Depth 5

if ($existingRulesetId) {
    # Update existing ruleset
    Write-Host "`nUpdating existing ruleset..." -ForegroundColor Cyan
    $response = Invoke-RestMethod -Uri "$baseUrl/$existingRulesetId" -Headers $headers -Method Put -Body $rulesetBody
} else {
    # Create new ruleset
    Write-Host "`nCreating new ruleset..." -ForegroundColor Cyan
    $response = Invoke-RestMethod -Uri $baseUrl -Headers $headers -Method Post -Body $rulesetBody
}

if ($response.success) {
    Write-Host "`nWAF rules deployed successfully!" -ForegroundColor Green
    Write-Host "  Ruleset ID: $($response.result.id)" -ForegroundColor DarkGray
    Write-Host "  Rule count: $($response.result.rules.Count)" -ForegroundColor DarkGray
} else {
    throw "Failed to deploy WAF rules: $($response.errors | ConvertTo-Json)"
}

Write-Host "`nFirewall sync complete." -ForegroundColor Green