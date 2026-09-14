@{
    RootModule           = 'MonitorSwitch.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'b7e4c1a2-9f03-4d6e-8c5a-1e2f3a4b5c6d'
    Author               = 'Owen Man'
    CompanyName          = 'ow-n'
    Copyright            = '(c) Owen Man. MIT licensed.'
    Description          = 'Geometry-based multi-monitor profile switching for Windows, with a refresh-rate policy that defaults to a safe cap.'
    PowerShellVersion    = '5.1'

    RequiredModules      = @(
        @{ ModuleName = 'DisplayConfig';   ModuleVersion = '6.0.0' }
        @{ ModuleName = 'powershell-yaml'; ModuleVersion = '0.4.7' }
    )

    FunctionsToExport    = @(
        'Get-MonitorSwitchConfig'
        'Get-MonitorSwitchProfile'
        'Get-MonitorSwitchStatus'
        'Set-MonitorSwitchProfile'
        'Set-MonitorSwitchRefresh'
        'Save-MonitorSwitchBaseline'
        'Show-MonitorSwitchIdentity'
        'New-MonitorSwitchShortcut'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('Monitor', 'Display', 'MultiMonitor', 'RefreshRate', 'Windows')
            LicenseUri = 'https://github.com/ow-n/monitor-switch/blob/main/LICENSE'
            ProjectUri = 'https://github.com/ow-n/monitor-switch'
        }
    }
}
