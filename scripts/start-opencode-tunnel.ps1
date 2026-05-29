$configFile  = "$env:USERPROFILE\.cloudflared\opencode-config.yml"
$cloudflared = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
$token       = "eyJhIjoiYjZjY2Q1MzFhNTExZjAwMjFmYThkOTBjMjljZDVhM2UiLCJzIjoiT1RCbU1XRmhaR0V0TjJObE5pMDBZbUUyTFRnM1l6WXRNalU1T0RWalpEQmxaR1JqIiwidCI6IjlmMTk3Y2IwLWQxOTctNGM3ZS1iZWQ2LWRkYzI4NTkzMzZmMyJ9"
$restart     = 5
if (-not (Test-Path $configFile))  { Write-Error "Config not found: $configFile";  exit 1 }
if (-not (Test-Path $cloudflared)) { Write-Error "cloudflared not found";           exit 1 }
while ($true) {
    & $cloudflared tunnel --config $configFile --token $token run
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds $restart
}
