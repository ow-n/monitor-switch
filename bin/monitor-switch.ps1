#Requires -Version 5.1
<#
.SYNOPSIS
    Monitor Switch - geometry-based multi-monitor profile switching for Windows.

.DESCRIPTION
    Commands:
      switch <name>   Apply a profile, then enforce the refresh policy
      list            Show configured profiles and what each keeps active
      status          Show the live layout, grid slots and refresh rates
      capture         Snapshot the current layout as the new baseline
      identify        Flash DisplayId + connection on each physical panel
      refresh         Re-apply the refresh policy only
      shortcuts       Generate one .bat launcher per profile
      config          Print the resolved config file path

.EXAMPLE
    .\monitor-switch.ps1 switch left
    .\monitor-switch.ps1 refresh -Policy max
    .\monitor-switch.ps1 status
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('switch', 'list', 'status', 'capture', 'identify', 'refresh', 'shortcuts', 'config')]
    [string]$Command = 'status',

    [Parameter(Position = 1)]
    [string]$Name,

    [ValidateSet('safe', 'max', 'native')]
    [string]$Policy,

    [int]$SafeHz,
    [switch]$SkipRefresh,
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

foreach ($dep in 'DisplayConfig', 'powershell-yaml') {
    if (-not (Get-Module -ListAvailable $dep)) {
        Write-Host "Missing dependency: $dep" -ForegroundColor Red
        Write-Host "Run install.ps1, or: Install-Module $dep -Scope CurrentUser -Force" -ForegroundColor Yellow
        exit 1
    }
}

Import-Module DisplayConfig -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '..\src\MonitorSwitch\MonitorSwitch.psd1') -Force -ErrorAction Stop

$common = @{}
if ($ConfigPath) { $common.ConfigPath = $ConfigPath }

try {
    switch ($Command) {
        'switch' {
            if (-not $Name) {
                Write-Host 'Usage: monitor-switch.ps1 switch <profile>' -ForegroundColor Red
                Get-MonitorSwitchProfile @common | Format-Table -AutoSize
                exit 1
            }
            Set-MonitorSwitchProfile -Name $Name -SkipRefresh:$SkipRefresh @common
            Get-MonitorSwitchStatus @common | Format-Table -AutoSize
        }
        'list'      { Get-MonitorSwitchProfile @common | Format-Table -AutoSize }
        'status'    { Get-MonitorSwitchStatus  @common | Format-Table -AutoSize }
        'capture'   { Save-MonitorSwitchBaseline; Get-MonitorSwitchStatus @common | Format-Table -AutoSize }
        'identify'  { Show-MonitorSwitchIdentity }
        'shortcuts' { New-MonitorSwitchShortcut @common }
        'config'    { (Get-MonitorSwitchConfig @common)['_path'] }
        'refresh' {
            $refreshArgs = @{}
            if ($Policy) { $refreshArgs.Policy = $Policy }
            if ($SafeHz) { $refreshArgs.SafeHz = $SafeHz }
            Set-MonitorSwitchRefresh @refreshArgs @common
        }
    }
}
catch {
    Write-Host "`n$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
