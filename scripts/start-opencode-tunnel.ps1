$configFile  = "$env:USERPROFILE\.cloudflared\opencode-config.yml"
$cloudflared = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
$restart     = 5
if (-not (Test-Path $configFile))  { Write-Error "Config not found: $configFile";  exit 1 }
if (-not (Test-Path $cloudflared)) { Write-Error "cloudflared not found";           exit 1 }
while ($true) {
    & $cloudflared tunnel --config $configFile run
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds $restart
}
