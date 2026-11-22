# Exercise every read-only code path. Applies nothing.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
    [string]$Setup
)

$ErrorActionPreference = 'Stop'

$repo  = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'src\MonitorSwitch\MonitorSwitch.psd1') -Force -ErrorAction Stop
Set-MonitorSwitchSetup -Name $Setup
Get-MonitorSwitchConfig | Out-Null

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
