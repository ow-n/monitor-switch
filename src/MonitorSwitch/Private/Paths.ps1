# Where config and machine-specific state live, plus section merging.

function Get-MonitorSwitchRoot {
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

function Get-MonitorSwitchDataDir {
    $dir = Join-Path $env:LOCALAPPDATA 'MonitorSwitch'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dir
}

function Get-MonitorSwitchStateDir {
    $dir = Join-Path (Get-MonitorSwitchDataDir) 'state'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dir
}

function Resolve-MonitorSwitchConfigPath {
    # Env override, then the per-machine copy, then the repo template.
    if ($env:MONITOR_SWITCH_CONFIG -and (Test-Path $env:MONITOR_SWITCH_CONFIG)) {
        return (Resolve-Path $env:MONITOR_SWITCH_CONFIG).Path
    }
    $userConfig = Join-Path (Get-MonitorSwitchDataDir) 'monitors.yaml'
    if (Test-Path $userConfig) { return $userConfig }

    $template = Join-Path (Get-MonitorSwitchRoot) 'monitors.yaml'
    if (Test-Path $template) { return $template }

    throw 'No monitors.yaml found. Run install.ps1, or set MONITOR_SWITCH_CONFIG.'
}

function Merge-MonitorSwitchSection {
    <#
    .SYNOPSIS
        Shallow-merge a per-profile override over a global config section.
    #>
    param($Base, $Override)

    $merged = @{}
    if ($Base) { foreach ($k in $Base.Keys) { $merged[$k] = $Base[$k] } }
    if ($Override) { foreach ($k in $Override.Keys) { $merged[$k] = $Override[$k] } }
    $merged
}

function Get-MonitorSwitchSection {
    <#
    .SYNOPSIS
        Read a config section, merged with the named profile's override if present.
    #>
    param($Config, [string]$Name, [string]$ProfileName)

    $base = if ($Config.ContainsKey($Name)) { $Config[$Name] } else { @{} }
    if (-not $ProfileName -or -not $Config.profiles.ContainsKey($ProfileName)) { return $base }

    $def = $Config.profiles[$ProfileName]
    $over = if ($def -is [System.Collections.IDictionary] -and $def.ContainsKey($Name)) { $def[$Name] } else { $null }
    Merge-MonitorSwitchSection -Base $base -Override $over
}
