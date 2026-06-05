# start-opencode-service.ps1
# Runs opencode web in WSL on port 4096.
# Accessible locally at http://localhost:4096 or via Cloudflare Tunnel at opencode.madebysoupy.dev.
# Sessions and config are stored in the WSL filesystem at ~/.local/share/opencode/.
#
# Per the official Windows/WSL docs: https://opencode.ai/docs/windows-wsl
#
# PATH strategy: we pipe a bash script via stdin instead of using -c "..."
# so that Windows tool paths containing spaces (Program Files) don't need
# shell-escaping gymnastics. Each export statement extends PATH incrementally.

$port = 4096
$wslUser = "soupy"

# ── Load credentials from .env ────────────────────────────────────────────────
# Scheduled tasks don't reliably inherit User-level env vars set after the task
# session started. Reading from .env at runtime is the only reliable source.
$envFile = Join-Path $PSScriptRoot '..\\.env'
$serverPassword = ''
$serverUsername = 'opencode'
if (Test-Path $envFile) {
    Get-Content $envFile | Where-Object { $_ -match '^OPENCODE_SERVER_(PASSWORD|USERNAME)=' } | ForEach-Object {
        $k, $v = $_ -split '=', 2
        if ($k -eq 'OPENCODE_SERVER_PASSWORD') { $serverPassword = $v.Trim() }
        if ($k -eq 'OPENCODE_SERVER_USERNAME') { $serverUsername = $v.Trim() }
    }
}

# Windows dev tools exposed to WSL via /mnt/c mount.
# Paths with spaces are safe here — they're inside a bash here-doc, not a -c string.
#
# Tool notes:
#   node  — shim at ~/.local/bin/node calls node.exe via interop (v24)
#   npm   — no-extension shell script in the nodejs dir, works natively
#   npx   — already present as shell script in nodejs dir
#   bun   — WSL-native install at ~/.bun/bin (v1.3)
#   go    — shim at ~/.local/bin/go calls go.exe via interop
#   git   — WSL-native install at /usr/bin/git
#   flutter/dart — Windows wrappers have CRLF line endings; they don't execute
#                  in bash.  Install Flutter for Linux in WSL to enable them:
#                  https://docs.flutter.dev/get-started/install/linux
$bashLauncher = @"
#!/bin/bash
# ── Linux-native tools (base) ───────────────────────────────────────────────
export PATH="\$HOME/.opencode/bin:\$HOME/.bun/bin:\$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"

# ── Windows tools via WSL /mnt/c interop ────────────────────────────────────
# Node.js  (C:\Program Files\nodejs) — node/go are shimmed in ~/.local/bin
export PATH="/mnt/c/Program Files/nodejs:\$PATH"

# Go  (C:\Program Files\Go\bin)
export PATH="/mnt/c/Program Files/Go/bin:\$PATH"

# Python  (C:\Python311)
export PATH="/mnt/c/Python311:/mnt/c/Python311/Scripts:\$PATH"

# ── OpenCode server auth ────────────────────────────────────────────────────
# Values loaded from .env above; injected into the WSL process at launch time.
$(if ($serverPassword) { "export OPENCODE_SERVER_PASSWORD='$serverPassword'" })
$(if ($serverUsername -and $serverUsername -ne 'opencode') { "export OPENCODE_SERVER_USERNAME='$serverUsername'" })

# ── Sync config from Windows to WSL ──────────────────────────────────────
# opencode-manager deploys config to the Windows path (C:\Users\JSCam\.config\opencode\).
# Sync it into WSL so opencode reads the latest config on every restart.
WIN_CONFIG="/mnt/c/Users/JSCam/.config/opencode"
WSL_CONFIG="\$HOME/.config/opencode"
if [ -f "\$WIN_CONFIG/opencode.jsonc" ]; then
  mkdir -p "\$WSL_CONFIG/agents" "\$WSL_CONFIG/commands" "\$WSL_CONFIG/plugins"
  cp -f "\$WIN_CONFIG/opencode.jsonc" "\$WSL_CONFIG/opencode.jsonc"
  cp -f "\$WIN_CONFIG/AGENTS.md" "\$WSL_CONFIG/AGENTS.md" 2>/dev/null
  cp -f "\$WIN_CONFIG/agents/"*.md "\$WSL_CONFIG/agents/" 2>/dev/null
  cp -f "\$WIN_CONFIG/commands/"*.md "\$WSL_CONFIG/commands/" 2>/dev/null
  cp -f "\$WIN_CONFIG/plugins/"*.ts "\$WSL_CONFIG/plugins/" 2>/dev/null
fi

# Port/hostname/cors are set via ~/.config/opencode/opencode.jsonc (server block).
# Do not duplicate them here — the config file is the single source of truth.
exec opencode web
"@

while ($true) {
    # Pipe the script via stdin — avoids -c quoting problems with spaces in Windows paths
    $bashLauncher | wsl.exe -d Ubuntu -u $wslUser -- bash
    Start-Sleep -Seconds 5
}