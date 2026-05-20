<#
.SYNOPSIS
    Restart the OpenCode service: kills the wrapper, opencode.exe, all children
    (MCP servers, language servers, cloudflared), then restarts the scheduled task.
#>

$taskName = 'OpenCode Service'
$port     = 4100

$Host.UI.RawUI.WindowTitle = 'Restart OpenCode Service'
Write-Host '=== Restart OpenCode Service ===' -ForegroundColor Cyan
Write-Host ''

# ── 1. Kill the wrapper process tree ───────────────────────────────────────
# The PS wrapper (start-opencode-service.ps1) is parent of opencode.exe.
# taskkill /F /T kills it + ALL descendants: opencode.exe, MCP servers,
# language servers, cloudflared.exe - everything in one shot.
Write-Host '  [1/4] Killing opencode process tree...' -ForegroundColor Yellow
$allProcs = Get-CimInstance Win32_Process
$wrappers = $allProcs | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'start-opencode-service' }
$killed = 0
foreach ($proc in $wrappers) {
    Write-Host ('      wrapper PID ' + $proc.ProcessId) -ForegroundColor DarkGray
    & taskkill /F /T /PID $proc.ProcessId 2>&1 | Out-Null
    $killed++
}
$ocProcs = Get-Process -Name 'opencode' -ErrorAction SilentlyContinue
foreach ($p in $ocProcs) {
    Write-Host ('      opencode.exe PID ' + $p.Id) -ForegroundColor DarkGray
    & taskkill /F /T /PID $p.Id 2>&1 | Out-Null
    $killed++
}
if ($killed -eq 0) {
    Write-Host '      nothing was running.' -ForegroundColor DarkGray
} else {
    Write-Host ('      killed ' + $killed + ' tree(s).') -ForegroundColor Yellow
}
Start-Sleep -Seconds 1

# ── 2. Kill orphaned MCP servers ────────────────────────────────────────────
# Previous sessions leave behind stale MCP processes with unrelated parents.
Write-Host ''
Write-Host '  [2/4] Cleaning up orphaned MCP servers...' -ForegroundColor Yellow
$mcpPatterns = @(
    'mcp-server-docker',
    'mcp-server-sequential-thinking',
    'mcp-server-cloudflare',
    'mcp-fetch-server',
    'notion-mcp-server',
    'plan-validator',
    '\.opencode[/\\]mcp'
)
$allProcs2 = Get-CimInstance Win32_Process
$mcpKilled = 0
$seen = @{}
foreach ($pattern in $mcpPatterns) {
    $allProcs2 | Where-Object { $_.CommandLine -match $pattern } | ForEach-Object {
        if (-not $seen[$_.ProcessId]) {
            $seen[$_.ProcessId] = $true
            & taskkill /F /T /PID $_.ProcessId 2>&1 | Out-Null
            Write-Host ('      ' + $_.Name + ' PID ' + $_.ProcessId) -ForegroundColor DarkGray
            $mcpKilled++
        }
    }
}
if ($mcpKilled -eq 0) {
    Write-Host '      no orphaned MCP servers found.' -ForegroundColor DarkGray
} else {
    Write-Host ('      killed ' + $mcpKilled + ' orphaned MCP process(es).') -ForegroundColor Yellow
}
Start-Sleep -Milliseconds 500

# ── 3. Stop scheduled task (clean up scheduler state) ───────────────────────
Write-Host ''
Write-Host '  [3/4] Stopping scheduled task...' -ForegroundColor Yellow
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
    Write-Host ('      task state: ' + (Get-ScheduledTask -TaskName $taskName).State) -ForegroundColor DarkGray
} else {
    Write-Host ('      WARNING: task not found: ' + $taskName) -ForegroundColor Red
}

# ── 4. Restart the scheduled task ───────────────────────────────────────────
Write-Host ''
Write-Host '  [4/4] Starting scheduled task...' -ForegroundColor White
if ($task) {
    Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 4
} else {
    Write-Host '      Cannot start - task not found. Start OpenCode manually.' -ForegroundColor Red
    Start-Sleep -Seconds 4
    exit 1
}

# ── 5. Verify ────────────────────────────────────────────────────────────────
$listening = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
Write-Host ''
if ($listening) {
    Write-Host ('  OK  opencode.exe listening on port ' + $port) -ForegroundColor Green
} else {
    Write-Host ('  WARN port ' + $port + ' not yet listening (may still be starting).') -ForegroundColor DarkYellow
}
Write-Host ''
Write-Host '  Done.' -ForegroundColor Green
Write-Host ''
Start-Sleep -Seconds 2
