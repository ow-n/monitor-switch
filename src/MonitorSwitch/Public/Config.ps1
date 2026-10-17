function Get-MonitorSwitchConfig {
    <#
    .SYNOPSIS
        Load and validate monitors.yaml.
    .EXAMPLE
        (Get-MonitorSwitchConfig)['_path']
    #>
    [CmdletBinding()]
    param([string]$Path)

    if (-not $Path) { $Path = Resolve-MonitorSwitchConfigPath }
    if (-not (Get-Module -ListAvailable powershell-yaml)) {
        throw 'powershell-yaml not installed. Run: Install-Module powershell-yaml -Scope CurrentUser'
    }
    Import-Module powershell-yaml -ErrorAction Stop

    $cfg = ConvertFrom-Yaml (Get-Content $Path -Raw)

    foreach ($key in 'layout', 'profiles', 'refresh') {
        if (-not $cfg.ContainsKey($key)) { throw "monitors.yaml is missing the '$key' section." }
    }

    $checks = @{
        'refresh.policy' = @{ Value = [string]$cfg.refresh.policy; Allowed = @('safe', 'max', 'native') }
    }
    if ($cfg.ContainsKey('hdr')) {
        $checks['hdr.policy'] = @{ Value = [string]$cfg.hdr.policy; Allowed = @('on', 'off', 'leave') }
        if ($cfg.hdr.ContainsKey('autoHdr')) {
            $checks['hdr.autoHdr'] = @{ Value = [string]$cfg.hdr.autoHdr; Allowed = @('on', 'off', 'leave') }
        }
    }
    if ($cfg.ContainsKey('osd')) {
        $checks['osd.policy'] = @{ Value = [string]$cfg.osd.policy; Allowed = @('apply', 'sync', 'leave') }
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
