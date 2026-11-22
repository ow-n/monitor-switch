# Exercise every read-only code path. Applies nothing.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
    [string]$Setup
)

$ErrorActionPreference = 'Stop'

$repo  = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'src\Module\MonitorSwitch.psd1') -Force -ErrorAction Stop
Set-MonitorSwitchSetup -Name $Setup
Get-MonitorSwitchConfig | Out-Null

Write-Host "`n=== config path ===" -ForegroundColor Cyan
(Get-MonitorSwitchConfig)['_path']

Write-Host "`n=== profiles (resolved against saved geometry) ===" -ForegroundColor Cyan
Get-MonitorSwitchProfile | Format-Table -AutoSize | Out-String -Width 160

Write-Host "`n=== live status ===" -ForegroundColor Cyan
Get-MonitorSwitchStatus | Format-Table -AutoSize | Out-String -Width 160

Write-Host "`n=== refresh policy dry run ===" -ForegroundColor Cyan
Set-MonitorSwitchRefreshRate -WhatIf

Write-Host "`n=== mandatory HDR-off dry run ===" -ForegroundColor Cyan
Disable-MonitorSwitchHdr -WhatIf

Write-Host "`n=== configured picture policy dry run ===" -ForegroundColor Cyan
Set-MonitorSwitchPicture -WhatIf

Write-Host "`n=== display comparison ===" -ForegroundColor Cyan
Compare-MonitorSwitchDisplay | Format-Table -AutoSize | Out-String -Width 160

Write-Host "`nSmoke test complete - nothing was applied." -ForegroundColor Green
