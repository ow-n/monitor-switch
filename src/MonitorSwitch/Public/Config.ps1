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
        $checks['hdr.policy'] = @{ Value = [string]$cfg.hdr.policy; Allowed = @('off') }
        if ($cfg.hdr.ContainsKey('autoHdr')) {
            $checks['hdr.autoHdr'] = @{ Value = [string]$cfg.hdr.autoHdr; Allowed = @('off') }
        }
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
                if ([string]::IsNullOrWhiteSpace($entry.Key) -or $entry.Value -isnot [string] -or $entry.Value -notin $script:InputCodes.Keys) {
                    throw "Invalid profiles.$profileName.inputs entry '$($entry.Key): $($entry.Value)'. Use DP1, DP2, HDMI1 or HDMI2."
                }
            }
        }
        if ($definition -is [System.Collections.IDictionary] -and $definition.ContainsKey('hdr')) {
            foreach ($field in 'policy', 'autoHdr') {
                if ($definition.hdr.ContainsKey($field)) {
                    $checks["profiles.$profileName.hdr.$field"] = @{
                        Value = [string]$definition.hdr[$field]
                        Allowed = @('off')
                    }
                }
            }
        }
    }
    if ($cfg.ContainsKey('osd')) {
        $checks['osd.policy'] = @{ Value = [string]$cfg.osd.policy; Allowed = @('apply', 'sync', 'leave') }
    }

    foreach ($name in $checks.Keys) {
        $c = $checks[$name]
        if ($c.Value -notin $c.Allowed) {
            if ($name -like '*hdr.*') {
                throw "HDR is locked off: $name must be off (got '$($c.Value)')."
            }
            throw "$name must be one of: $($c.Allowed -join ', ') (got '$($c.Value)')."
        }
    }

    $cfg['_path'] = $Path
    $cfg
}
