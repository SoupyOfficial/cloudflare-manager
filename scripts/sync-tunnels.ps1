<#
.SYNOPSIS
    Sync tunnel configurations to local cloudflared config files.
.DESCRIPTION
    Reads tunnel YAML definitions and generates cloudflared config files
    at ~/.cloudflared/<tunnel-name>-config.yml ready for: cloudflared tunnel run
#>
param(
    [string]$TunnelName = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$rootDir = Split-Path $PSScriptRoot -Parent
$tunnelsDir = Join-Path $rootDir 'infrastructure/tunnels'

Write-Host "Syncing tunnel configurations..." -ForegroundColor Cyan

$tunnelFiles = Get-ChildItem -Path $tunnelsDir -Filter '*.yaml' -File
if ($tunnelFiles.Count -eq 0) {
    Write-Host "No tunnel configurations found in $tunnelsDir" -ForegroundColor Yellow
    return
}

foreach ($file in $tunnelFiles) {
    if ($file.Name -eq 'README.md') { continue }

    Write-Host "`nProcessing: $($file.Name)" -ForegroundColor White

    $content = Get-Content $file.FullName -Raw
    if ($content -notmatch '(?m)^tunnel:\s*$') {
        Write-Host "  Skipping — no top-level tunnel block found" -ForegroundColor DarkGray
        continue
    }

    # Simple YAML parsing for tunnel config
    $tunnelName = if ($content -match '(?m)^\s*name:\s*(.+)$') { $matches[1].Trim() } else { '''' }
    $tunnelId   = if ($content -match '(?m)^\s*id:\s*"?([0-9a-f-]{36})"?\s*$') { $matches[1].Trim() } else { '''' }

    if (-not $tunnelName) {
        Write-Host "  Skipping — no tunnel name found" -ForegroundColor Yellow
        continue
    }

    if ($TunnelName -and $tunnelName -ne $TunnelName) {
        Write-Host "  Skipping — not matching filter: $TunnelName" -ForegroundColor DarkGray
        continue
    }

    if (-not $tunnelId) {
        Write-Host "  ERROR: Tunnel ID is empty in $($file.Name). Run: cloudflared tunnel info $tunnelName" -ForegroundColor Red
        continue
    }

    # Parse ingress rules from YAML (hostname + service pairs)
    $ingressLines    = @()
    $inIngress       = $false
    $currentHostname = ''
    $currentService  = ''

    foreach ($line in ($content -split "`n")) {
        $trimmed = $line.TrimEnd()

        if ($trimmed -match '^ingress:') {
            $inIngress = $true
            continue
        }

        if (-not $inIngress) { continue }

        # Stop at any new top-level key
        if ($trimmed -match '^[a-zA-Z]' -and $trimmed -notmatch '^ ') {
            $inIngress = $false
            continue
        }

        if ($trimmed -match '^ *- hostname:\s*(.+)$') {
            # Save previous host+service rule if complete
            if ($currentHostname -and $currentService) {
                $ingressLines += "  - hostname: $currentHostname"
                $ingressLines += "    service: $currentService"
            }
            $currentHostname = $matches[1].Trim()
            $currentService  = ''
        } elseif ($trimmed -match '^ +service:\s*(.+)$') {
            $svc = $matches[1].Trim()
            if ($currentHostname) {
                $currentService = $svc
            } else {
                # Indented service without preceding hostname = catch-all for current rule
                $ingressLines += "  - service: $svc"
            }
        } elseif ($trimmed -match '^ *- service:\s*(.+)$') {
            # Catch-all inline: "  - service: http_status:404"
            if ($currentHostname -and $currentService) {
                $ingressLines += "  - hostname: $currentHostname"
                $ingressLines += "    service: $currentService"
            }
            $ingressLines    += "  - service: $($matches[1].Trim())"
            $currentHostname  = ''
            $currentService   = ''
        }
    }

    # Flush last rule
    if ($currentHostname -and $currentService) {
        $ingressLines += "  - hostname: $currentHostname"
        $ingressLines += "    service: $currentService"
    }

    $ruleCount = ($ingressLines | Where-Object { $_ -match 'hostname:' }).Count
    Write-Host "  Tunnel : $tunnelName"            -ForegroundColor DarkGray
    Write-Host "  ID     : $tunnelId"              -ForegroundColor DarkGray
    Write-Host "  Ingress: $ruleCount hostname rules" -ForegroundColor DarkGray

    # Build cloudflared config YAML
    # Use USERPROFILE on Windows and HOME on macOS/Linux.
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { '' }
    if (-not $homeDir) {
        throw "Could not determine home directory. Set USERPROFILE or HOME."
    }
    $configDir  = Join-Path $homeDir '.cloudflared'
    $credsFile  = Join-Path $configDir "$tunnelId.json"
    $configFile = Join-Path $configDir "$tunnelName-config.yml"

    $ingressBlock = $ingressLines -join "`n"
    $configYaml = @"
tunnel: $tunnelId
credentials-file: $credsFile

ingress:
$ingressBlock
"@

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would write config to: $configFile" -ForegroundColor Yellow
        Write-Host $configYaml -ForegroundColor DarkGray
        continue
    }

    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }

    Set-Content -Path $configFile -Value $configYaml -Encoding UTF8
    Write-Host "  Config written to : $configFile" -ForegroundColor Green
    Write-Host "  Run with          : cloudflared tunnel --config `"$configFile`" run $tunnelName" -ForegroundColor DarkGray
}

Write-Host "`nTunnel sync complete." -ForegroundColor Green
