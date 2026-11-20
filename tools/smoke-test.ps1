# Exercise every read-only code path. Applies nothing.
#
# -SeedFrom optionally bootstraps per-machine state from an existing
# Tools\Monitors install so the test has a real baseline to resolve against.
[CmdletBinding()]
param(
    [string]$SeedFrom,
    [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
    [string]$Setup
)

$ErrorActionPreference = 'Stop'

$repo  = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'src\MonitorSwitch\MonitorSwitch.psd1') -Force -ErrorAction Stop
if ($Setup) { Set-MonitorSwitchSetup -Name $Setup }
Get-MonitorSwitchConfig | Out-Null

$state = & (Get-Module MonitorSwitch) { Get-MonitorSwitchStateDir }

if ($SeedFrom) {
    if ($Setup -and $Setup -ne 'home-pc') { throw '-SeedFrom is only for a legacy home PC baseline.' }
    Copy-Item (Join-Path $SeedFrom 'profiles\five.xml')       (Join-Path $state 'baseline.xml')   -Force
    Copy-Item (Join-Path $SeedFrom 'profiles\positions.json') (Join-Path $state 'positions.json') -Force
    Write-Host "Seeded baseline from $SeedFrom" -ForegroundColor Green
}

Write-Host "`n=== config path ===" -ForegroundColor Cyan
(Get-MonitorSwitchConfig)['_path']

Write-Host "`n=== profiles (resolved against baseline geometry) ===" -ForegroundColor Cyan
Get-MonitorSwitchProfile | Format-Table -AutoSize | Out-String -Width 160

Write-Host "`n=== live status ===" -ForegroundColor Cyan
Get-MonitorSwitchStatus | Format-Table -AutoSize | Out-String -Width 160

Write-Host "`n=== refresh policy dry run ===" -ForegroundColor Cyan
Set-MonitorSwitchRefresh -WhatIf

Write-Host "`n=== hdr policy dry run (forced 'off' to exercise the path) ===" -ForegroundColor Cyan
Set-MonitorSwitchHdr -Policy off -WhatIf

Write-Host "`n=== configured osd policy dry run ===" -ForegroundColor Cyan
Set-MonitorSwitchOsd -WhatIf

Write-Host "`n=== parity report ===" -ForegroundColor Cyan
Test-MonitorSwitchParity | Format-Table -AutoSize | Out-String -Width 160

Write-Host "`nSmoke test complete - nothing was applied." -ForegroundColor Green
