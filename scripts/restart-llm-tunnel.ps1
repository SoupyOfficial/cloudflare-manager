<#
.SYNOPSIS
    Kill and restart the LLM (Ollama) Cloudflare tunnel.
.DESCRIPTION
    Stops any cloudflared.exe process serving ollama-home-config.yml,
    then opens a new terminal window running the tunnel.
#>

$configFile = "$env:USERPROFILE\.cloudflared\ollama-home-config.yml"
$tunnelId   = "7ee20289-1222-4023-89af-d3b688005abb"

$Host.UI.RawUI.WindowTitle = "Restart LLM Tunnel"
Write-Host "=== Restart LLM Tunnel ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $configFile)) {
    Write-Host "  ERROR: Config not found: $configFile" -ForegroundColor Red
    Start-Sleep -Seconds 4
    exit 1
}

# Find and kill existing cloudflared for this tunnel
$killed = 0
Get-CimInstance Win32_Process -Filter "Name='cloudflared.exe'" | ForEach-Object {
    if ($_.CommandLine -match 'ollama-home-config' -or $_.CommandLine -match [regex]::Escape($tunnelId)) {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "  Stopped: cloudflared PID $($_.ProcessId)" -ForegroundColor Yellow
        $killed++
    }
}

if ($killed -eq 0) {
    Write-Host "  No LLM tunnel was running." -ForegroundColor DarkGray
} else {
    Write-Host "  Stopped $killed cloudflared process(es)." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 600
}

# Launch new tunnel in a persistent window
Write-Host ""
Write-Host "  Starting LLM tunnel..." -ForegroundColor White
Start-Process powershell.exe -ArgumentList @(
    "-NoProfile", "-NoExit",
    "-Command", "& { `$host.UI.RawUI.WindowTitle = 'LLM Tunnel'; cloudflared tunnel --config '$configFile' run }"
) -WindowStyle Normal

Write-Host "  Done — LLM tunnel window opened." -ForegroundColor Green
Write-Host ""
Start-Sleep -Seconds 2
