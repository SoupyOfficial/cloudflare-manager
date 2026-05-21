param(
    [ValidateSet("portal", "native")]
    [string]$Mode = "portal"
)

$repoRoot = "C:\Users\JSCam\Documents\Development\cloudflare-manager"
Set-Location $repoRoot

if ($env:OPENCODE_FRONTEND -in @("portal", "native")) {
    $Mode = $env:OPENCODE_FRONTEND
}

function Get-OpencodePath {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\opencode\opencode.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\opencode.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $cmd = Get-Command opencode -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    return $null
}

function Start-NativeOpenCode {
    $opencode = Get-OpencodePath
    if (-not $opencode) {
        Write-Error "opencode.exe not found"
        Start-Sleep -Seconds 5
        return
    }

    & $opencode serve --hostname 127.0.0.1 --port 4100
}

function Start-PortalOpenCode {
    $opencodeDirs = @(
        "$env:USERPROFILE\.bun\bin",
        "$env:LOCALAPPDATA\Programs\opencode",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
    )
    foreach ($dir in $opencodeDirs) {
        if ((Test-Path $dir) -and ($env:Path -notlike "*$dir*")) {
            $env:Path = "$dir;$env:Path"
        }
    }

    $bunLocal = "$env:USERPROFILE\.bun\bin\bun.exe"
    $portalDist = "$env:APPDATA\npm\node_modules\openportal\dist\index.js"
    if ((Test-Path $bunLocal) -and (Test-Path $portalDist)) {
        & $bunLocal $portalDist --hostname 127.0.0.1 --port 4100 --opencode-port 4101 --name cloudflare-manager
        return
    }

    $portal = Get-Command openportal -ErrorAction SilentlyContinue
    if ($portal) {
        & $portal.Source --hostname 127.0.0.1 --port 4100 --opencode-port 4101 --name cloudflare-manager
        return
    }

    $bunx = Get-Command bunx -ErrorAction SilentlyContinue
    if ($bunx) {
        & $bunx.Source openportal --hostname 127.0.0.1 --port 4100 --opencode-port 4101 --name cloudflare-manager
        return
    }

    $npx = Get-Command npx -ErrorAction SilentlyContinue
    if ($npx) {
        & $npx.Source -y openportal --hostname 127.0.0.1 --port 4100 --opencode-port 4101 --name cloudflare-manager
        return
    }

    Write-Warning "openportal/bunx not found. Falling back to native opencode serve mode."
    Start-NativeOpenCode
}

while ($true) {
    if ($Mode -eq "portal") {
        Start-PortalOpenCode
    }
    else {
        Start-NativeOpenCode
    }

    Start-Sleep -Seconds 5
}