$bun = "$env:USERPROFILE\.bun\bin\bun.exe"
$portal = "$env:APPDATA\npm\node_modules\openportal\dist\index.js"
$exclude = "C:\Users\JSCam\Documents\Development\cloudflare-manager"

# Ensure opencode is on PATH so spawned openportal processes can find it
@("$env:LOCALAPPDATA\Programs\opencode", "$env:USERPROFILE\.opencode\bin", "$env:USERPROFILE\.bun\bin", "$env:LOCALAPPDATA\Microsoft\WinGet\Links") | ForEach-Object {
    if ((Test-Path $_) -and ($env:Path -notlike "*$_*")) { $env:Path = "$_;$env:Path" }
}

$oc = (Get-Command opencode -ErrorAction SilentlyContinue)?.Source
if (-not $oc) {
    $oc = @(
        "$env:LOCALAPPDATA\Programs\opencode\opencode.exe",
        "$env:USERPROFILE\.opencode\bin\opencode.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\opencode.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $oc) { Write-Error "opencode not found"; exit 1 }
if (-not (Test-Path $bun))    { Write-Error "bun not found at $bun"; exit 1 }
if (-not (Test-Path $portal)) { Write-Error "openportal dist not found at $portal"; exit 1 }

$dirs = (& $oc db "select worktree from project where worktree is not null and worktree <> '/'" --format json 2>$null | ConvertFrom-Json).worktree

foreach ($dir in $dirs) {
    if ($dir -eq $exclude) { continue }
    if (-not (Test-Path $dir)) { Write-Host "SKIP (missing dir): $dir"; continue }
    $name = Split-Path $dir -Leaf
    Write-Host "Starting backend: $name  ($dir)"
    Start-Process -FilePath $bun -ArgumentList @($portal, "run", "--directory", $dir, "--name", $name, "--hostname", "127.0.0.1") -WindowStyle Hidden
    # Wait for this process to bind its port before starting the next, avoiding get-port-please race conditions
    Start-Sleep -Seconds 2
}

Write-Host "Waiting for final registrations..."
Start-Sleep -Seconds 2

$instances = (Get-Content "$env:USERPROFILE\.portal.json" | ConvertFrom-Json).instances
Write-Host "`nRegistered instances ($($instances.Count)):"
$instances | ForEach-Object { Write-Host "  $($_.name.PadRight(22)) port=$($_.backendPort)" }
