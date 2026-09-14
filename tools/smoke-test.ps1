# Exercise every read-only code path. Applies nothing.
#
# -SeedFrom optionally bootstraps per-machine state from an existing
# Tools\Monitors install so the test has a real baseline to resolve against.
[CmdletBinding()]
param(
    [string]$SeedFrom
)

$ErrorActionPreference = 'Stop'

$repo  = Split-Path -Parent $PSScriptRoot
$data  = Join-Path $env:LOCALAPPDATA 'MonitorSwitch'
$state = Join-Path $data 'state'
New-Item -ItemType Directory -Path $state -Force | Out-Null

if (-not (Test-Path (Join-Path $data 'monitors.yaml'))) {
    Copy-Item (Join-Path $repo 'monitors.yaml') (Join-Path $data 'monitors.yaml')
    Write-Host "Seeded config -> $data" -ForegroundColor Green
}

if ($SeedFrom) {
    Copy-Item (Join-Path $SeedFrom 'profiles\five.xml')       (Join-Path $state 'baseline.xml')   -Force
    Copy-Item (Join-Path $SeedFrom 'profiles\positions.json') (Join-Path $state 'positions.json') -Force
    Write-Host "Seeded baseline from $SeedFrom" -ForegroundColor Green
}

Import-Module DisplayConfig -ErrorAction Stop
Import-Module (Join-Path $repo 'src\MonitorSwitch\MonitorSwitch.psd1') -Force -ErrorAction Stop

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

Write-Host "`n=== osd sync dry run ===" -ForegroundColor Cyan
Set-MonitorSwitchOsd -Policy sync -WhatIf

Write-Host "`n=== parity report ===" -ForegroundColor Cyan
Test-MonitorSwitchParity | Format-Table -AutoSize | Out-String -Width 160

Write-Host "`nSmoke test complete - nothing was applied." -ForegroundColor Green
