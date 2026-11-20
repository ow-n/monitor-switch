# Where config and machine-specific state live, plus section merging.

$script:MonitorSwitchSetup = ''

function Set-MonitorSwitchSetup {
    <#
    .SYNOPSIS
        Select an isolated setup for this module session. Nothing is applied.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Selects only module-session context; no persisted state or display settings change.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
        [string]$Name
    )

    $template = Join-Path (Get-MonitorSwitchRoot) "setups\$Name\monitors.yaml"
    if (-not (Test-Path -LiteralPath $template)) {
        throw "Unknown setup '$Name'. Add setups\$Name\monitors.yaml first."
    }
    $script:MonitorSwitchSetup = $Name
}

function Get-MonitorSwitchRoot {
    # This file sits at <root>/src/MonitorSwitch/Private, so climb three levels.
    Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

function Get-MonitorSwitchDataDir {
    $dir = Join-Path $env:LOCALAPPDATA 'MonitorSwitch'
    if ($script:MonitorSwitchSetup) {
        $dir = Join-Path $dir "setups\$script:MonitorSwitchSetup"
    }
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dir
}

function Get-MonitorSwitchStateDir {
    $dir = Join-Path (Get-MonitorSwitchDataDir) 'state'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dir
}

function Resolve-MonitorSwitchConfigPath {
    if ($script:MonitorSwitchSetup) {
        $userConfig = Join-Path (Get-MonitorSwitchDataDir) 'monitors.yaml'
        if (Test-Path -LiteralPath $userConfig) { return $userConfig }
        return Join-Path (Get-MonitorSwitchRoot) "setups\$script:MonitorSwitchSetup\monitors.yaml"
    }
    # Explicit setups never consult a legacy environment override.
    if ($env:MONITOR_SWITCH_CONFIG) {
        return (Resolve-Path $env:MONITOR_SWITCH_CONFIG).Path
    }
    $userConfig = Join-Path (Get-MonitorSwitchDataDir) 'monitors.yaml'
    if (Test-Path $userConfig) { return $userConfig }

    throw 'Choose a setup: run install.ps1 -Setup home-pc, home-laptop, or office-laptop. Use the same -Setup with the CLI.'
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
