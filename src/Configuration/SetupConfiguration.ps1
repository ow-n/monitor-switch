function Get-MonitorSwitchConfig {
    <#
    .SYNOPSIS
        Load and validate a setup's PowerShell data file.
    .EXAMPLE
        (Get-MonitorSwitchConfig)['_path']
    #>
    [CmdletBinding()]
    param([Alias('ConfigPath')][string]$Path)

    if (-not $Path) { $Path = Resolve-MonitorSwitchConfigPath }
    $cfg = Import-PowerShellDataFile -LiteralPath $Path -ErrorAction Stop

    foreach ($key in 'layout', 'profiles', 'refresh') {
        if (-not $cfg.ContainsKey($key)) { throw "$Path is missing the '$key' section." }
    }

    if ($cfg.ContainsKey('mode')) {
        if ($cfg.mode -notin @('handoff', 'alignment')) {
            throw 'mode must be handoff or alignment.'
        }
        if ($cfg.mode -eq 'alignment') {
            foreach ($profileName in $cfg.profiles.Keys) {
                if ($cfg.profiles[$profileName].select -isnot [string] -or $cfg.profiles[$profileName].select -ne 'all') {
                    throw "Alignment-only setups cannot disable displays: profiles.$profileName.select must be all."
                }
            }
        }
    }

    foreach ($axis in 'columnNames', 'rowNames') {
        if (-not $cfg.layout.ContainsKey($axis)) { continue }
        $names = $cfg.layout[$axis]
        if ($names -isnot [System.Collections.IDictionary]) { throw "layout.$axis must map grid indexes to slot names." }
        foreach ($key in $names.Keys) {
            $index = 0
            if (-not [int]::TryParse([string]$key, [ref]$index) -or [string]::IsNullOrWhiteSpace([string]$names[$key])) {
                throw "layout.$axis needs integer indexes and non-empty names."
            }
        }
        if (@($names.Values | Sort-Object -Unique).Count -ne $names.Count) {
            throw "layout.$axis names must be unique."
        }
    }

    $checks = @{
        'refresh.policy' = @{ Value = [string]$cfg.refresh.policy; Allowed = @('safe', 'max', 'native') }
    }
    if ($cfg.ContainsKey('hdr')) {
        throw 'HDR is locked off and not configurable. Remove the hdr section.'
    }
    foreach ($profileName in $cfg.profiles.Keys) {
        $definition = $cfg.profiles[$profileName]
        if ($definition -is [System.Collections.IDictionary] -and $definition.ContainsKey('inputs')) {
            if ($cfg.ContainsKey('mode') -and $cfg.mode -eq 'alignment') {
                throw 'Alignment-only setups cannot switch monitor inputs.'
            }
            if ($definition.inputs -isnot [System.Collections.IDictionary]) {
                throw "profiles.$profileName.inputs must map captured slot names to input names."
            }
            foreach ($entry in $definition.inputs.GetEnumerator()) {
                if ([string]::IsNullOrWhiteSpace($entry.Key) -or $entry.Value -isnot [string] -or $entry.Value -notin $script:MonitorInputValues.Keys) {
                    throw "Invalid profiles.$profileName.inputs entry '$($entry.Key): $($entry.Value)'. Use DP1, DP2, HDMI1 or HDMI2."
                }
            }
        }
        if ($definition -is [System.Collections.IDictionary] -and $definition.ContainsKey('hdr')) {
            throw "HDR is locked off and not configurable. Remove profiles.$profileName.hdr."
        }
    }
    if ($cfg.ContainsKey('osd')) { throw 'Rename the osd section to picture.' }
    if ($cfg.ContainsKey('picture')) {
        $checks['picture.policy'] = @{ Value = [string]$cfg.picture.policy; Allowed = @('apply', 'sync', 'leave') }
    }

    foreach ($name in $checks.Keys) {
        $c = $checks[$name]
        if ($c.Value -notin $c.Allowed) {
            throw "$name must be one of: $($c.Allowed -join ', ') (got '$($c.Value)')."
        }
    }

    $cfg['_path'] = $Path
    $cfg
}

function Set-MonitorSwitchSetup {
    <#
    .SYNOPSIS
        Select the machine/location context without applying a profile.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Selects module-session context; no persisted state or display settings change.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
        [string]$Name
    )
    $path = Join-Path (Get-MonitorSwitchRoot) "setups\$Name\config.psd1"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Unknown setup '$Name'. No setups\$Name\config.psd1 in this checkout."
    }
    $script:MonitorSwitchSetup = $Name
}

function Get-MonitorSwitchRoot { $script:RepositoryRoot }

function Get-MonitorSwitchStateDir {
    if (-not $script:MonitorSwitchSetup) { throw 'Choose a setup with -Setup home-pc, home-laptop or office-laptop.' }
    Join-Path (Get-MonitorSwitchRoot) "state\$script:MonitorSwitchSetup"
}

function Resolve-MonitorSwitchConfigPath {
    if (-not $script:MonitorSwitchSetup) { throw 'Choose a setup with -Setup home-pc, home-laptop or office-laptop.' }
    Join-Path (Get-MonitorSwitchRoot) "setups\$script:MonitorSwitchSetup\config.psd1"
}

function Get-MonitorSwitchSection {
    param($Config, [string]$Name, [string]$ProfileName)
    $section = @{}
    if ($Config.ContainsKey($Name)) {
        foreach ($key in $Config[$Name].Keys) { $section[$key] = $Config[$Name][$key] }
    }
    if ($ProfileName -and $Config.profiles.ContainsKey($ProfileName) -and $Config.profiles[$ProfileName].ContainsKey($Name)) {
        foreach ($key in $Config.profiles[$ProfileName][$Name].Keys) {
            $section[$key] = $Config.profiles[$ProfileName][$Name][$key]
        }
    }
    $section
}
