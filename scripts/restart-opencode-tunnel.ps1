<#
.SYNOPSIS
    Restart the OpenCode Cloudflare tunnel via its Scheduled Task.
.DESCRIPTION
    Stops the "Cloudflare Tunnel - opencode-origin" scheduled task, kills any
    lingering cloudflared processes for this tunnel, then starts the task again.

    If the task is missing, prints instructions and exits with a non-zero code.
    Run scripts/install-opencode-tunnel-task.ps1 once to register it.
#>

$taskName   = "Cloudflare Tunnel - opencode-origin"
$configFile = "$env:USERPROFILE\.cloudflared\opencode-config.yml"
$tunnelId   = "475f52fb-60a2-4177-b193-617fdc703e4e"

$Host.UI.RawUI.WindowTitle = "Restart OpenCode Tunnel"
Write-Host "=== Restart OpenCode Tunnel ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $configFile)) {
    Write-Host "  ERROR: Config not found: $configFile" -ForegroundColor Red
    Start-Sleep -Seconds 4
    exit 1
}

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Host "  ERROR: Scheduled task '$taskName' not found." -ForegroundColor Red
    Write-Host "         Run scripts/install-opencode-tunnel-task.ps1 first." -ForegroundColor Yellow
    Start-Sleep -Seconds 4
    exit 1
}

# [1/3] Stop the scheduled task
Write-Host "  [1/3] Stopping scheduled task..." -ForegroundColor Yellow
Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 800
Write-Host "        State: $((Get-ScheduledTask -TaskName $taskName).State)" -ForegroundColor DarkGray

# [2/3] Kill any lingering cloudflared processes for this tunnel
Write-Host ""
Write-Host "  [2/3] Killing lingering cloudflared processes..." -ForegroundColor Yellow
$killed = 0
Get-CimInstance Win32_Process -Filter "Name='cloudflared.exe'" | ForEach-Object {
    if ($_.CommandLine -match 'opencode-config' -or $_.CommandLine -match [regex]::Escape($tunnelId)) {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "        Stopped PID $($_.ProcessId)" -ForegroundColor DarkGray
        $killed++
    }
}
if ($killed -eq 0) {
    Write-Host "        No lingering processes." -ForegroundColor DarkGray
} else {
    Write-Host "        Killed $killed process(es)." -ForegroundColor Yellow
}
Start-Sleep -Milliseconds 600

# [3/3] Start the scheduled task
Write-Host ""
Write-Host "  [3/3] Starting scheduled task..." -ForegroundColor White
Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 4

$state = (Get-ScheduledTask -TaskName $taskName).State
Write-Host "        Task state: $state" -ForegroundColor DarkGray

if ($state -eq "Running") {
    Write-Host "  Done — OpenCode tunnel is running." -ForegroundColor Green
} else {
    Write-Host "  WARN: Task state is '$state' — may still be starting." -ForegroundColor Yellow
}

Write-Host ""
Start-Sleep -Seconds 2
