#Requires -Version 5.1
<#
.SYNOPSIS
    Monitor Switch - geometry-based multi-monitor profile switching for Windows.

.DESCRIPTION
    Commands:
      switch <name>   Apply a profile; all brings back the saved full arrangement
      list            Show configured profiles and what each keeps active
      status          Show the live layout, grid slots and refresh rates
      compare         Compare readable settings across displays
      capture         Save the full arrangement used by ALL and subset profiles
      identify        Flash DisplayId + connection on each physical panel
      refresh         Re-apply the refresh policy only
      hdr             Disable and verify Windows HDR, Auto HDR, and HDR playback
      picture         Apply or synchronize physical-monitor picture settings
      config          Print the resolved config file path

.EXAMPLE
    .\monitor-switch.ps1 switch left -Setup home-pc
    .\monitor-switch.ps1 switch all -Setup home-laptop
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('switch', 'list', 'status', 'compare', 'capture', 'identify',
        'refresh', 'hdr', 'picture', 'config')]
    [string]$Command = 'status',

    [Parameter(Position = 1)]
    [string]$Name,

    [string]$Policy,
    [int]$SafeHz,
    [string]$Setting,
    [int]$Value,
    [string]$Reference,
    [switch]$SkipRefresh,
    [switch]$SkipPicture,
    [switch]$WhatIf,
    [string]$ConfigPath,
    [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
    [string]$Setup
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\src\Module\MonitorSwitch.psd1') -Force -ErrorAction Stop

$common = @{}
if ($ConfigPath) { $common.ConfigPath = $ConfigPath }

# Forward only the switches actually supplied, so config defaults survive.
$opt = @{}
foreach ($n in 'Policy', 'SafeHz', 'Setting', 'Value', 'Reference') {
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
    $allowed = switch ($Command) {
        'switch' { 'Name', 'SkipRefresh', 'SkipPicture', 'WhatIf' }
        'capture' { 'WhatIf' }
        'refresh' { 'Policy', 'SafeHz', 'WhatIf' }
        'hdr' { 'WhatIf' }
        'picture' { 'Policy', 'Setting', 'Value', 'Reference', 'WhatIf' }
        default { @() }
    }
    foreach ($option in 'Name', 'Policy', 'SafeHz', 'Setting', 'Value', 'Reference', 'SkipRefresh', 'SkipPicture', 'WhatIf') {
        if ($PSBoundParameters.ContainsKey($option) -and $option -notin $allowed) {
            throw "'$Command' does not support -$option."
        }
    }
    switch ($Command) {
        'switch' {
            if (-not $Name) {
                Write-Host 'Usage: monitor-switch.ps1 switch <profile>' -ForegroundColor Red
                Get-MonitorSwitchProfile @common | Format-Table -AutoSize
                exit 1
            }
            Set-MonitorSwitchProfile -Name $Name -SkipRefresh:$SkipRefresh -SkipPicture:$SkipPicture -WhatIf:$WhatIf @common
            Get-MonitorSwitchStatus @common | Format-Table -AutoSize
        }
        'list' { Get-MonitorSwitchProfile @common | Format-Table -AutoSize }
        'status' { Get-MonitorSwitchStatus  @common | Format-Table -AutoSize }
        'capture' { Save-MonitorSwitchLayout -WhatIf:$WhatIf @common; Get-MonitorSwitchStatus @common | Format-Table -AutoSize }
        'identify' { Show-MonitorSwitchDisplayIdentity }
        'config' { (Get-MonitorSwitchConfig @common)['_path'] }

        'compare' {
            $rows = @(Compare-MonitorSwitchDisplay @common)
            $rows | Format-Table -AutoSize
            $drift = @($rows | Where-Object Drift)
            if ($drift) {
                Write-Host ('Drift on: {0}' -f ($drift.Attribute -join ', ')) -ForegroundColor Yellow
                exit 1
            }
            Write-Host 'All displays agree.' -ForegroundColor Green
        }

        'refresh' { $a = Select-Opt 'Policy', 'SafeHz'; Set-MonitorSwitchRefreshRate @a @common -WhatIf:$WhatIf }
        'hdr' { Disable-MonitorSwitchHdr -WhatIf:$WhatIf }
        'picture' { $a = Select-Opt 'Policy', 'Setting', 'Value', 'Reference'; Set-MonitorSwitchPicture @a @common -WhatIf:$WhatIf }
    }
}
catch {
    Write-Host "`n$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
