@{
    RootModule           = 'MonitorSwitch.psm1'
    ModuleVersion        = '3.1.0'
    GUID                 = 'b7e4c1a2-9f03-4d6e-8c5a-1e2f3a4b5c6d'
    Author               = 'Owen Man'
    CompanyName          = 'ow-n'
    Copyright            = '(c) Owen Man. MIT licensed.'
    Description          = 'Saved monitor arrangements, verified input handoffs, refresh and picture settings, with mandatory HDR-off protection.'
    PowerShellVersion    = '5.1'

    FunctionsToExport    = @(
        'Get-MonitorSwitchConfig'
        'Get-MonitorSwitchProfile'
        'Get-MonitorSwitchStatus'
        'Get-MonitorSwitchCapture'
        'Set-MonitorSwitchSetup'
        'Set-MonitorSwitchProfile'
        'Set-MonitorSwitchRefreshRate'
        'Disable-MonitorSwitchHdr'
        'Set-MonitorSwitchPicture'
        'Compare-MonitorSwitchDisplay'
        'Save-MonitorSwitchLayout'
        'Show-MonitorSwitchDisplayIdentity'
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
