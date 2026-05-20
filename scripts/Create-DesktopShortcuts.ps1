<#
.SYNOPSIS
    Creates desktop shortcuts for Cloudflare tunnel management.
.DESCRIPTION
    Generates .lnk shortcut files on the Windows Desktop that launch
    the tunnel restart and status scripts with a single double-click.

    Run this script once to set up shortcuts. Re-run if scripts move.
#>

$scriptDir  = $PSScriptRoot
$desktopDir = [System.Environment]::GetFolderPath('Desktop')
$wsh        = New-Object -ComObject WScript.Shell
$psExe      = 'powershell.exe'

Write-Host '=== Create Desktop Shortcuts ===' -ForegroundColor Cyan
Write-Host "  Scripts folder : $scriptDir"  -ForegroundColor DarkGray
Write-Host "  Desktop folder : $desktopDir" -ForegroundColor DarkGray
Write-Host ''

function New-TunnelShortcut {
    param(
        [string]$ShortcutName,
        [string]$ScriptPath,
        [string]$Description,
        [string]$IconSource = '',
        [int]$IconIndex = 0,
        [switch]$NoExit
    )

    $lnkPath = Join-Path $desktopDir "$ShortcutName.lnk"
    $noExitFlag = if ($NoExit) { '-NoExit ' } else { '' }
    $lnkArgs = "-NoProfile -ExecutionPolicy Bypass ${noExitFlag}-File `"$ScriptPath`""

    $lnk = $wsh.CreateShortcut($lnkPath)
    $lnk.TargetPath       = $psExe
    $lnk.Arguments        = $lnkArgs
    $lnk.Description      = $Description
    $lnk.WorkingDirectory = Split-Path $ScriptPath -Parent
    if ($IconSource) { $lnk.IconLocation = "$IconSource,$IconIndex" }
    $lnk.Save()
    Write-Host "  OK  $ShortcutName.lnk" -ForegroundColor Green
}

$shell32  = 'C:\Windows\System32\shell32.dll'
$imageres = 'C:\Windows\System32\imageres.dll'

New-TunnelShortcut `
    -ShortcutName 'Restart OpenCode Service' `
    -ScriptPath   "$scriptDir\restart-opencode-service.ps1" `
    -Description  'Stop and restart the OpenCode Service scheduled task (port 4100)' `
    -IconSource   $shell32 -IconIndex 19

New-TunnelShortcut `
    -ShortcutName 'Restart OpenCode Tunnel' `
    -ScriptPath   "$scriptDir\restart-opencode-tunnel.ps1" `
    -Description  'Kill and restart the OpenCode Cloudflare tunnel (port 4100)' `
    -IconSource   $shell32 -IconIndex 238

New-TunnelShortcut `
    -ShortcutName 'Restart LLM Tunnel' `
    -ScriptPath   "$scriptDir\restart-llm-tunnel.ps1" `
    -Description  'Kill and restart the LLM (Ollama) Cloudflare tunnel (port 11434)' `
    -IconSource   $shell32 -IconIndex 238

New-TunnelShortcut `
    -ShortcutName 'Restart All Tunnels' `
    -ScriptPath   "$scriptDir\restart-all-tunnels.ps1" `
    -Description  'Kill and restart both OpenCode and LLM tunnels' `
    -IconSource   $shell32 -IconIndex 76

New-TunnelShortcut `
    -ShortcutName 'Tunnel Status' `
    -ScriptPath   "$scriptDir\tunnel-status.ps1" `
    -Description  'Show which Cloudflare tunnels are currently running' `
    -IconSource   $imageres -IconIndex 109 `
    -NoExit

New-TunnelShortcut `
    -ShortcutName 'Tunnel Health Check' `
    -ScriptPath   "$scriptDir\health-check.ps1" `
    -Description  'Check reachability of all public Cloudflare endpoints' `
    -IconSource   $imageres -IconIndex 82 `
    -NoExit

Write-Host ''
Write-Host '  6 shortcuts created on your Desktop!' -ForegroundColor Green
Write-Host '  Run each with a double-click.' -ForegroundColor DarkGray
Write-Host ''
