<#
.SYNOPSIS
    Registers the "Cloudflare Tunnel - opencode-origin" Scheduled Task.
.DESCRIPTION
    Creates (or replaces) the Windows Scheduled Task that runs the OpenCode
    cloudflared tunnel on user logon with auto-restart on crash.
    Run this ONCE after provisioning the machine, then use
    restart-opencode-tunnel.ps1 for day-to-day restarts.

    Prerequisites:
      - C:\AI\llm-host\start-opencode-tunnel.ps1 must exist
      - ~/.cloudflared/opencode-config.yml must exist
      - ~/.cloudflared/475f52fb-60a2-4177-b193-617fdc703e4e.json must exist
#>

$taskName  = "Cloudflare Tunnel - opencode-origin"
$scriptDir = "C:\AI\llm-host"
$script    = Join-Path $scriptDir "start-opencode-tunnel.ps1"
$configFile = "$env:USERPROFILE\.cloudflared\opencode-config.yml"

$Host.UI.RawUI.WindowTitle = "Install OpenCode Tunnel Task"
Write-Host "=== Install: $taskName ===" -ForegroundColor Cyan
Write-Host ""

# --- Pre-flight checks ----------------------------------------------------
$ok = $true

if (-not (Test-Path $script)) {
    Write-Host "  ERROR: Watchdog script not found: $script" -ForegroundColor Red
    Write-Host "         Create it from the repo template and try again." -ForegroundColor Yellow
    $ok = $false
}

if (-not (Test-Path $configFile)) {
    Write-Host "  ERROR: Tunnel config not found: $configFile" -ForegroundColor Red
    Write-Host "         Run scripts/sync-tunnels.ps1 first." -ForegroundColor Yellow
    $ok = $false
}

if (-not $ok) { Start-Sleep -Seconds 4; exit 1 }

Write-Host "  Pre-flight checks passed." -ForegroundColor DarkGray
Write-Host ""

# --- Build task components ------------------------------------------------
$action = New-ScheduledTaskAction `
    -Execute    "powershell.exe" `
    -Argument   "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""

$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit 0 `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable

$principal = New-ScheduledTaskPrincipal `
    -UserId     "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType  Interactive `
    -RunLevel   Limited

# --- Register (overwrite if already exists) -------------------------------
Write-Host "  Registering task..." -ForegroundColor White
Register-ScheduledTask `
    -TaskName   $taskName `
    -Action     $action `
    -Trigger    $trigger `
    -Settings   $settings `
    -Principal  $principal `
    -Description "Runs cloudflared for the opencode-origin tunnel (475f52fb) at logon. Auto-restarts on crash." `
    -Force | Out-Null

Write-Host "  Task registered: $taskName" -ForegroundColor Green
Write-Host ""

# --- Start immediately -----------------------------------------------------
Write-Host "  Starting task now..." -ForegroundColor White
Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 4

$state = (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue).State
Write-Host "  Task state: $state" -ForegroundColor DarkGray

if ($state -eq "Running") {
    Write-Host "  OpenCode tunnel task is running." -ForegroundColor Green
} else {
    Write-Host "  WARN: Task state is '$state' — may still be starting." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Setup complete." -ForegroundColor Green
Write-Host "  Use restart-opencode-tunnel.ps1 for day-to-day restarts." -ForegroundColor DarkGray
Write-Host ""
Start-Sleep -Seconds 2
