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

$port    = 4096
$wslUser = "soupy"

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
# OPENCODE_SERVER_PASSWORD: set in the Windows environment (User or System)
# to enable basic auth protection on the server. If unset, server is open.
# OPENCODE_SERVER_USERNAME: defaults to 'opencode' if not overridden.
if [ -n '${env:OPENCODE_SERVER_PASSWORD}' ]; then
  export OPENCODE_SERVER_PASSWORD='${env:OPENCODE_SERVER_PASSWORD}'
fi
if [ -n '${env:OPENCODE_SERVER_USERNAME}' ]; then
  export OPENCODE_SERVER_USERNAME='${env:OPENCODE_SERVER_USERNAME}'
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