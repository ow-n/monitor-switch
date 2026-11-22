@{
    RootModule           = 'MonitorSwitch.psm1'
    ModuleVersion        = '2.0.0'
    GUID                 = 'b7e4c1a2-9f03-4d6e-8c5a-1e2f3a4b5c6d'
    Author               = 'Owen Man'
    CompanyName          = 'ow-n'
    Copyright            = '(c) Owen Man. MIT licensed.'
    Description          = 'Geometry-based multi-monitor profile switching for Windows, with declarative refresh, HDR, and OSD policies that default to a safe refresh cap.'
    PowerShellVersion    = '5.1'

    FunctionsToExport    = @(
        'Get-MonitorSwitchConfig'
        'Get-MonitorSwitchProfile'
        'Get-MonitorSwitchStatus'
        'Set-MonitorSwitchSetup'
        'Set-MonitorSwitchProfile'
        'Set-MonitorSwitchRefresh'
        'Set-MonitorSwitchHdr'
        'Set-MonitorSwitchOsd'
        'Test-MonitorSwitchParity'
        'Save-MonitorSwitchBaseline'
        'Show-MonitorSwitchIdentity'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('Monitor', 'Display', 'MultiMonitor', 'RefreshRate', 'HDR', 'DDC', 'Windows')
            LicenseUri = 'https://github.com/ow-n/monitor-switch/blob/main/LICENSE'
            ProjectUri = 'https://github.com/ow-n/monitor-switch'
        }
    }
}
