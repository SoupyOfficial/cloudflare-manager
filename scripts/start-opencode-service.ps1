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

function Update-OpenPortalWindowsPatches {
    function Set-NormalizedFileContent {
        param(
            [string]$FilePath,
            [string]$AlreadyPatchedPattern,
            [string]$MatchPattern,
            [string]$Replacement,
            [string]$SuccessMessage,
            [string]$SkipMessage
        )

        if (-not (Test-Path -LiteralPath $FilePath)) {
            return
        }

        $content = Get-Content -LiteralPath $FilePath -Raw
        $normalizedContent = $content -replace "`r`n", "`n"
        if ($AlreadyPatchedPattern -and ($normalizedContent -match $AlreadyPatchedPattern)) {
            return
        }

        $normalizedReplacement = $Replacement -replace "`r`n", "`n"
        if (-not [regex]::IsMatch($normalizedContent, $MatchPattern)) {
            Write-Warning $SkipMessage
            return
        }

        $updated = [regex]::Replace(
            $normalizedContent,
            $MatchPattern,
            { param($match) $normalizedReplacement },
            1
        )
        Set-Content -LiteralPath $FilePath -Value $updated -NoNewline
        Write-Host $SuccessMessage
    }

    $instancesRouteFile = "$env:APPDATA\npm\node_modules\openportal\web\server\_routes\api\instances.mjs"
    $instancesReplacement = @'
    const configuredProcessInstances = readConfig().instances.flatMap((instance) => {
        const provider = getInstanceProvider(instance);
        if (provider === "claude") return [];
        const backendPid = getInstanceBackendPid(instance);
        const backendRunning = isProcessRunning(backendPid);
        const webRunning = isProcessRunning(instance.webPid);
        if (!backendRunning && !webRunning) return [];
        const backendPort = getInstanceBackendPort(instance);
        return {
            id: instance.id,
            provider,
            name: instance.name || directoryName(instance.directory),
            directory: instance.directory,
            port: backendPort,
            hostname: instance.hostname,
            opencodePid: instance.opencodePid ?? null,
            backendPid,
            webPid: instance.webPid,
            startedAt: instance.startedAt,
            instanceType: instance.instanceType,
            containerId: instance.containerId,
            source: "config",
            version: provider === "codex" ? "codex app-server" : "opencode",
            sessionStats: null,
            state: "running",
            status: webRunning && instance.startedAt ? `Managed by OpenPortal since ${new Date(instance.startedAt).toLocaleString()}` : "Registered by openportal run"
        };
    });
    const discoveredInstances = await discoverBackendServers();
    const uniqueInstances = /* @__PURE__ */ new Map();
    for (const instance of [...claudeInstances, ...configuredProcessInstances, ...discoveredInstances]) {
        const key = `${instance.provider}:${instance.port}:${instance.directory}`;
        if (!uniqueInstances.has(key)) uniqueInstances.set(key, instance);
    }
    const instances = [...uniqueInstances.values()];
'@
    Set-NormalizedFileContent `
        -FilePath $instancesRouteFile `
        -AlreadyPatchedPattern 'configuredProcessInstances' `
        -MatchPattern '(?ms)^\s*const discoveredInstances = await discoverBackendServers\(\);\n\s*const instances = \[\.\.\.claudeInstances, \.\.\.discoveredInstances\];' `
        -Replacement $instancesReplacement `
        -SuccessMessage 'Patched OpenPortal instances API for Windows process-backed instances.' `
        -SkipMessage 'OpenPortal instances API layout changed; skipping Windows patch.'

    $sessionsRouteFile = "$env:APPDATA\npm\node_modules\openportal\web\server\_routes\api\opencode\[port]\sessions.mjs"
    $sessionsReplacement = @'
import { i as defineHandler } from "../../../../_libs/h3+rou3+srvx.mjs";
import { t as createOpencodeClient } from "../../../../_libs/opencode-ai__sdk.mjs";
import { readFileSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import { getOpencodeBaseUrl } from "../../lib/opencode_client.mjs";
import { parsePort } from "../../lib/validation.mjs";
//#region src/server/opencode/[port]/sessions.ts
function getDirectoryForPort(port) {
	try {
		const config = JSON.parse(readFileSync(join(homedir(), ".portal.json"), "utf-8"));
		const instance = (config.instances ?? []).find((i) => {
			const bp = i.backendPort ?? i.opencodePort;
			return bp === port || String(bp) === String(port);
		});
		return instance ? instance.directory : null;
	} catch {
		return null;
	}
}
function sortSessions(sessions) {
	return [...sessions].sort((left, right) => {
		const leftTime = left.time?.updated ?? left.time?.created ?? 0;
		const rightTime = right.time?.updated ?? right.time?.created ?? 0;
		return rightTime - leftTime;
	});
}
var sessions_default = defineHandler(async (event) => {
	const port = parsePort(event);
	const directory = getDirectoryForPort(port);
	const clientOptions = { baseUrl: getOpencodeBaseUrl(port) };
	if (directory) clientOptions.directory = directory;
	const result = (await createOpencodeClient(clientOptions).session.list()).data ?? [];
	return sortSessions(result);
});
//#endregion
export { sessions_default as default };
'@
    Set-NormalizedFileContent `
        -FilePath $sessionsRouteFile `
        -AlreadyPatchedPattern 'getDirectoryForPort' `
        -MatchPattern '(?ms)^import \{ i as defineHandler \} from ".*?export \{ sessions_default as default \};' `
        -Replacement $sessionsReplacement `
        -SuccessMessage 'Patched OpenPortal sessions API for per-instance directory scoping.' `
        -SkipMessage 'OpenPortal sessions API layout changed; skipping per-instance patch.'
}

function Start-ProjectBackends {
    param([string]$ExcludeDirectory)

    $opencode = Get-OpencodePath
    if (-not $opencode) { return }

    try {
        $projectsJson = & $opencode db "select worktree from project where worktree is not null and worktree <> '/' order by time_updated desc" --format json 2>$null
        $projects = $projectsJson | ConvertFrom-Json
    } catch {
        Write-Warning "Could not query opencode project list: $_"
        return
    }

    # Ensure opencode is on PATH so spawned openportal processes can find it
    @("$env:USERPROFILE\.bun\bin", "$env:LOCALAPPDATA\Programs\opencode", "$env:LOCALAPPDATA\Microsoft\WinGet\Links") | ForEach-Object {
        if ((Test-Path $_) -and ($env:Path -notlike "*$_*")) { $env:Path = "$_;$env:Path" }
    }

    $bunLocal = "$env:USERPROFILE\.bun\bin\bun.exe"
    $portalDist = "$env:APPDATA\npm\node_modules\openportal\dist\index.js"
    $usesBun = (Test-Path $bunLocal) -and (Test-Path $portalDist)
    $portalExe = if (-not $usesBun) {
        $cmd = Get-Command openportal -ErrorAction SilentlyContinue
        if ($cmd) { $cmd.Source } else { $null }
    }

    if (-not $usesBun -and -not $portalExe) {
        Write-Warning "openportal not found; skipping project backend pre-start."
        return
    }

    $excluded = $ExcludeDirectory.TrimEnd('\', '/')

    foreach ($project in $projects) {
        $dir = $project.worktree
        if (-not $dir) { continue }
        $dir = $dir.TrimEnd('\', '/')
        if ($dir -eq $excluded) { continue }
        if (-not (Test-Path $dir)) { continue }

        $name = Split-Path $dir -Leaf

        if ($usesBun) {
            Start-Process -FilePath $bunLocal `
                -ArgumentList @($portalDist, "run", "--directory", $dir, "--name", $name, "--hostname", "127.0.0.1") `
                -WindowStyle Hidden
        } else {
            Start-Process -FilePath $portalExe `
                -ArgumentList @("run", "--directory", $dir, "--name", $name, "--hostname", "127.0.0.1") `
                -WindowStyle Hidden
        }
        Write-Host "  Started backend: $name"
        # Stagger starts so each process binds its port before the next one calls get-port-please
        Start-Sleep -Seconds 2
    }
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
        Update-OpenPortalWindowsPatches
        Write-Host "Pre-starting all known project backends..."
        $backendsScript = Join-Path $repoRoot "scripts\start-project-backends.ps1"
        $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($pwsh -and (Test-Path $backendsScript)) {
            Start-Process -FilePath $pwsh.Source -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $backendsScript) -WindowStyle Hidden
        }
        & $bunLocal $portalDist --hostname 127.0.0.1 --port 4100 --opencode-port 4101 --name cloudflare-manager
        return
    }

    $portal = Get-Command openportal -ErrorAction SilentlyContinue
    if ($portal) {
        Write-Host "Pre-starting all known project backends..."
        $backendsScript = Join-Path $repoRoot "scripts\start-project-backends.ps1"
        $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($pwsh -and (Test-Path $backendsScript)) {
            Start-Process -FilePath $pwsh.Source -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $backendsScript) -WindowStyle Hidden
        }
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