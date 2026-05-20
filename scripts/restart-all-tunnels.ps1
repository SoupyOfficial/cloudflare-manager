<#
.SYNOPSIS
    Kill and restart both the OpenCode and LLM Cloudflare tunnels.
#>

$opencodeConfig = "$env:USERPROFILE\.cloudflared\opencode-config.yml"
$llmConfig      = "$env:USERPROFILE\.cloudflared\ollama-home-config.yml"

$Host.UI.RawUI.WindowTitle = "Restart All Tunnels"
Write-Host "=== Restart All Cloudflare Tunnels ===" -ForegroundColor Cyan
Write-Host ""

# Kill ALL cloudflared processes
$procs = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
if ($procs) {
    $procs | Stop-Process -Force
    Write-Host "  Stopped $($procs.Count) cloudflared process(es)." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 800
} else {
    Write-Host "  No cloudflared processes were running." -ForegroundColor DarkGray
}

# Restart OpenCode tunnel
if (Test-Path $opencodeConfig) {
    Write-Host ""
    Write-Host "  Starting OpenCode tunnel..." -ForegroundColor White
    Start-Process powershell.exe -ArgumentList @(
        "-NoProfile", "-NoExit",
        "-Command", "& { `$host.UI.RawUI.WindowTitle = 'OpenCode Tunnel'; cloudflared tunnel --config '$opencodeConfig' run }"
    ) -WindowStyle Normal
    Write-Host "  OpenCode tunnel window opened." -ForegroundColor Green
    Start-Sleep -Milliseconds 400
} else {
    Write-Host "  SKIP: opencode-config.yml not found." -ForegroundColor Yellow
}

# Restart LLM tunnel
if (Test-Path $llmConfig) {
    Write-Host ""
    Write-Host "  Starting LLM tunnel..." -ForegroundColor White
    Start-Process powershell.exe -ArgumentList @(
        "-NoProfile", "-NoExit",
        "-Command", "& { `$host.UI.RawUI.WindowTitle = 'LLM Tunnel'; cloudflared tunnel --config '$llmConfig' run }"
    ) -WindowStyle Normal
    Write-Host "  LLM tunnel window opened." -ForegroundColor Green
} else {
    Write-Host "  SKIP: ollama-home-config.yml not found." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  All tunnels restarted!" -ForegroundColor Green
Start-Sleep -Seconds 2
