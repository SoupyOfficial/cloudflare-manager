<#
.SYNOPSIS
    Restart both Cloudflare tunnels (OpenCode + LLM).
.DESCRIPTION
    - OpenCode tunnel: managed via "Cloudflare Tunnel - opencode-origin" Scheduled Task
    - LLM tunnel: managed via the "Cloudflared" Windows Service (+ fallback task)
    Each tunnel is stopped, any lingering cloudflared processes killed, then restarted.
#>

$opencodeTaskName = "Cloudflare Tunnel - opencode-origin"
$opencodeTunnelId = "475f52fb-60a2-4177-b193-617fdc703e4e"
$llmServiceName   = "Cloudflared"
$llmTunnelId      = "7ee20289-1222-4023-89af-d3b688005abb"

$Host.UI.RawUI.WindowTitle = "Restart All Tunnels"
Write-Host "=== Restart All Cloudflare Tunnels ===" -ForegroundColor Cyan
Write-Host ""

# ── 1. Stop OpenCode tunnel task ─────────────────────────────────────────────
Write-Host "  [1/4] Stopping OpenCode tunnel task..." -ForegroundColor Yellow
$ocTask = Get-ScheduledTask -TaskName $opencodeTaskName -ErrorAction SilentlyContinue
if ($ocTask) {
    Stop-ScheduledTask -TaskName $opencodeTaskName -ErrorAction SilentlyContinue
    Write-Host "        Stopped." -ForegroundColor DarkGray
} else {
    Write-Host "        WARN: Task '$opencodeTaskName' not found." -ForegroundColor Yellow
    Write-Host "        Run scripts/install-opencode-tunnel-task.ps1 first." -ForegroundColor Yellow
}

# ── 2. Stop LLM tunnel (Windows Service) ─────────────────────────────────────
Write-Host ""
Write-Host "  [2/4] Stopping LLM tunnel service..." -ForegroundColor Yellow
$llmSvc = Get-Service -Name $llmServiceName -ErrorAction SilentlyContinue
if ($llmSvc) {
    Stop-Service -Name $llmServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
    Write-Host "        Service state: $((Get-Service -Name $llmServiceName).Status)" -ForegroundColor DarkGray
} else {
    Write-Host "        WARN: Service '$llmServiceName' not found." -ForegroundColor Yellow
}

# Kill any lingering cloudflared processes
Start-Sleep -Milliseconds 500
$remaining = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
if ($remaining) {
    $remaining | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "        Killed $($remaining.Count) lingering cloudflared process(es)." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 600
}

# ── 3. Start LLM tunnel service ───────────────────────────────────────────────
Write-Host ""
Write-Host "  [3/4] Starting LLM tunnel service..." -ForegroundColor White
if ($llmSvc) {
    Start-Service -Name $llmServiceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "        Service state: $((Get-Service -Name $llmServiceName).Status)" -ForegroundColor DarkGray
    Write-Host "        LLM tunnel started." -ForegroundColor Green
} else {
    Write-Host "        Cannot start — service not found." -ForegroundColor Red
}

# ── 4. Start OpenCode tunnel task ─────────────────────────────────────────────
Write-Host ""
Write-Host "  [4/4] Starting OpenCode tunnel task..." -ForegroundColor White
if ($ocTask) {
    Start-ScheduledTask -TaskName $opencodeTaskName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 4
    $state = (Get-ScheduledTask -TaskName $opencodeTaskName).State
    Write-Host "        Task state: $state" -ForegroundColor DarkGray
    Write-Host "        OpenCode tunnel started." -ForegroundColor Green
} else {
    Write-Host "        Cannot start — task not registered." -ForegroundColor Red
}

Write-Host ""
Write-Host "  All tunnels restarted!" -ForegroundColor Green
Write-Host ""
Start-Sleep -Seconds 2
