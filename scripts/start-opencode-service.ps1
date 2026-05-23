# start-opencode-service.ps1
# Runs opencode web in WSL on port 4096.
# Accessible locally at http://localhost:4096 or via Cloudflare Tunnel at opencode.madebysoupy.dev.
# Sessions and config are stored in the WSL filesystem at ~/.local/share/opencode/.
#
# Per the official Windows/WSL docs: https://opencode.ai/docs/windows-wsl

$port    = 4096
$wslUser = "soupy"
# Use a minimal explicit Linux PATH — avoids bash syntax errors from Windows
# PATH entries containing spaces/parens (e.g. "Program Files (x86)") being
# appended by WSL interop when $PATH is expanded.
# opencode web is a standalone server; no project directory required.
# Ref: https://opencode.ai/docs/windows-wsl

while ($true) {
    wsl.exe -d Ubuntu -u $wslUser -- bash -c "PATH=~/.opencode/bin:~/.bun/bin:~/.local/bin:/usr/local/bin:/usr/bin:/bin opencode web --hostname 0.0.0.0 --port $port"
    Start-Sleep -Seconds 5
}