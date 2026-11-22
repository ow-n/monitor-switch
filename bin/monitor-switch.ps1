#Requires -Version 5.1
<#
.SYNOPSIS
    Monitor Switch - geometry-based multi-monitor profile switching for Windows.

.DESCRIPTION
    Commands:
      switch <name>   Apply a profile, then enforce refresh + HDR + OSD policies
      restore         Restore this setup's full captured alignment
      list            Show configured profiles and what each keeps active
      status          Show the live layout, grid slots and refresh rates
      parity          Compare every readable setting across displays, flag drift
      capture         Snapshot the current layout as the new baseline
      identify        Flash DisplayId + connection on each physical panel
      refresh         Re-apply the refresh policy only
      hdr             Re-apply the HDR policy only
      osd             Re-apply the monitor OSD policy only
      config          Print the resolved config file path

.EXAMPLE
    .\monitor-switch.ps1 switch left -Setup home-pc
    .\monitor-switch.ps1 restore -Setup home-laptop
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('switch', 'restore', 'list', 'status', 'parity', 'capture', 'identify',
        'refresh', 'hdr', 'osd', 'config')]
    [string]$Command = 'status',

    [Parameter(Position = 1)]
    [string]$Name,

    [string]$Policy,
    [int]$SafeHz,
    [int]$SdrNits,
    [string]$Setting,
    [int]$Value,
    [string]$Reference,
    [switch]$SkipRefresh,
    [switch]$SkipHdr,
    [switch]$SkipOsd,
    [switch]$WhatIf,
    [string]$ConfigPath,
    [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
    [string]$Setup
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\src\MonitorSwitch\MonitorSwitch.psd1') -Force -ErrorAction Stop

$common = @{}
if ($ConfigPath) { $common.ConfigPath = $ConfigPath }

# Forward only the switches actually supplied, so config defaults survive.
$opt = @{}
foreach ($n in 'Policy', 'SafeHz', 'SdrNits', 'Setting', 'Value', 'Reference') {
    if ($PSBoundParameters.ContainsKey($n)) { $opt[$n] = $PSBoundParameters[$n] }
}
function Select-Opt {
    param([string[]]$Names)
    $picked = @{}
    foreach ($n in $Names) { if ($opt.ContainsKey($n)) { $picked[$n] = $opt[$n] } }
    $picked
}

try {
    if (-not $Setup) { throw 'Choose a setup with -Setup home-pc, home-laptop or office-laptop.' }
    Set-MonitorSwitchSetup -Name $Setup
    if ($Command -eq 'restore') {
        $Command = 'switch'
        $Name = 'all'
    }
    switch ($Command) {
        'switch' {
            if (-not $Name) {
                Write-Host 'Usage: monitor-switch.ps1 switch <profile>' -ForegroundColor Red
                Get-MonitorSwitchProfile @common | Format-Table -AutoSize
                exit 1
            }
            Set-MonitorSwitchProfile -Name $Name -SkipRefresh:$SkipRefresh -SkipHdr:$SkipHdr -SkipOsd:$SkipOsd -WhatIf:$WhatIf @common
            Get-MonitorSwitchStatus @common | Format-Table -AutoSize
        }
        'list' { Get-MonitorSwitchProfile @common | Format-Table -AutoSize }
        'status' { Get-MonitorSwitchStatus  @common | Format-Table -AutoSize }
        'capture' { Save-MonitorSwitchBaseline -WhatIf:$WhatIf @common; Get-MonitorSwitchStatus @common | Format-Table -AutoSize }
        'identify' { Show-MonitorSwitchIdentity }
        'config' { (Get-MonitorSwitchConfig @common)['_path'] }

        'parity' {
            $rows = @(Test-MonitorSwitchParity @common)
            $rows | Format-Table -AutoSize
            $drift = @($rows | Where-Object Drift)
            if ($drift) {
                Write-Host ('Drift on: {0}' -f ($drift.Attribute -join ', ')) -ForegroundColor Yellow
                exit 1
            }
            Write-Host 'All displays agree.' -ForegroundColor Green
        }

        'refresh' { $a = Select-Opt 'Policy', 'SafeHz'; Set-MonitorSwitchRefresh @a @common -WhatIf:$WhatIf }
        'hdr' { $a = Select-Opt 'Policy', 'SdrNits'; Set-MonitorSwitchHdr @a @common -WhatIf:$WhatIf }
        'osd' { $a = Select-Opt 'Policy', 'Setting', 'Value', 'Reference'; Set-MonitorSwitchOsd @a @common -WhatIf:$WhatIf }
    }
}
catch {
    Write-Host "`n$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
