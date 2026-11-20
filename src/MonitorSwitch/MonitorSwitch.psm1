#Requires -Version 5.1
Set-StrictMode -Version Latest

# Windows-only: everything here rides on user32/dxva2 and the CCD wrapper.
if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
    throw 'MonitorSwitch requires Windows.'
}

foreach ($folder in 'Private', 'Public') {
    Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter *.ps1 -ErrorAction SilentlyContinue |
        ForEach-Object { . $_.FullName }
}

Export-ModuleMember -Function `
    Get-MonitorSwitchConfig, Get-MonitorSwitchProfile, Get-MonitorSwitchStatus,
Set-MonitorSwitchSetup, Set-MonitorSwitchProfile, Set-MonitorSwitchRefresh, Set-MonitorSwitchHdr,
Set-MonitorSwitchOsd, Test-MonitorSwitchParity, Save-MonitorSwitchBaseline,
Show-MonitorSwitchIdentity, New-MonitorSwitchShortcut
