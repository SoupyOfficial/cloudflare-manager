<#
.SYNOPSIS
    Show which Cloudflare tunnels are currently running.
#>

$Host.UI.RawUI.WindowTitle = "Tunnel Status"
Write-Host "=== Cloudflare Tunnel Status ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host ""

$tunnels = @(
    @{ Name = "OpenCode Tunnel"; ConfigPattern = "opencode-config"; TunnelId = "475f52fb-60a2-4177-b193-617fdc703e4e"; Hostnames = "opencode-origin.madebysoupy.dev, opencode-ws.madebysoupy.dev"; Port = 4100 },
    @{ Name = "LLM Tunnel";      ConfigPattern = "ollama-home-config"; TunnelId = "7ee20289-1222-4023-89af-d3b688005abb"; Hostnames = "llm.madebysoupy.dev";                                  Port = 11434 }
)

$allProcs = Get-CimInstance Win32_Process -Filter "Name='cloudflared.exe'" -ErrorAction SilentlyContinue

foreach ($t in $tunnels) {
    $matchingProcs = $allProcs | Where-Object {
        $_.CommandLine -match $t.ConfigPattern -or $_.CommandLine -match [regex]::Escape($t.TunnelId)
    }

    if ($matchingProcs) {
        $pids = ($matchingProcs | ForEach-Object { $_.ProcessId }) -join ", "
        Write-Host "  ✔ $($t.Name)" -ForegroundColor Green
        Write-Host "    PID(s)   : $pids"           -ForegroundColor DarkGray
        Write-Host "    Hostname : $($t.Hostnames)"  -ForegroundColor DarkGray
    } else {
        Write-Host "  ✘ $($t.Name)" -ForegroundColor Red
        Write-Host "    Hostname : $($t.Hostnames)"  -ForegroundColor DarkGray
        Write-Host "    Status   : NOT RUNNING"       -ForegroundColor Red
    }

    # Check local service port
    $portInUse = Get-NetTCPConnection -LocalPort $t.Port -State Listen -ErrorAction SilentlyContinue
    if ($portInUse) {
        Write-Host "    Port     : :$($t.Port) LISTENING" -ForegroundColor DarkGray
    } else {
        Write-Host "    Port     : :$($t.Port) not listening" -ForegroundColor DarkYellow
    }
    Write-Host ""
}

# Overall cloudflared summary
$total = ($allProcs | Measure-Object).Count
Write-Host "--- Cloudflared processes running: $total ---" -ForegroundColor $(if ($total -gt 0) { 'Cyan' } else { 'DarkGray' })
Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
