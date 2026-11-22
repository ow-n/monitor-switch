#Requires -Version 5.1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Hardware doubles accept production arguments.')]
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$module = Import-Module (Join-Path $repo 'src\MonitorSwitch\MonitorSwitch.psd1') -Force -PassThru
try {
    & $module {
        param($Template)
        function Assert-Equal($Actual, $Expected) {
            if ($Actual -ne $Expected) { throw "Expected '$Expected', got '$Actual'." }
        }
        $script:wall = @(
            [pscustomobject]@{ DisplayId = 1; DevicePath = 'top-dp'; X = 0; Y = -1440; Device = 'gdi7' }
            [pscustomobject]@{ DisplayId = 2; DevicePath = 'bottom-dp'; X = 0; Y = 0; Device = 'gdi5' }
            [pscustomobject]@{ DisplayId = 3; DevicePath = 'bottom-hdmi'; X = -3440; Y = 0; Device = 'gdi1' }
            [pscustomobject]@{ DisplayId = 4; DevicePath = 'top-hdmi'; X = -3440; Y = -1440; Device = 'gdi2' }
        )
        $script:disabled = @(1, 2)
        $script:panelInputs = @{ gdi7 = 17; gdi5 = 17; gdi1 = 17; gdi2 = 17 }
        $script:primaryId = 4
        $script:ignoreWritesFor = ''
        function script:Get-MonitorSwitchBaselineGeometry { $script:wall }
        function script:Get-MonitorSwitchDisplayInfo {
            foreach ($d in $script:wall) {
                $active = $d.DisplayId -notin $script:disabled
                [pscustomobject]@{
                    DisplayId = $d.DisplayId; DevicePath = $d.DevicePath; Active = $active
                    Primary = $d.DisplayId -eq $script:primaryId
                    GdiDeviceName = if ($active) { $d.Device }
                }
            }
        }
        function script:Test-MonitorSwitchBaseline { $true }
        function script:Import-MonitorSwitchBaselineConfig {
            $layout = [pscustomobject]@{ Disabled = @() }
            $layout | Add-Member ScriptMethod SetPrimary { param($Id) }
            $layout | Add-Member ScriptMethod Disable { param($Id) $this.Disabled += $Id }
            $layout
        }
        function script:Invoke-MonitorSwitchLayout { param($Config) $script:disabled = $Config.Disabled }
        function script:Set-MonitorSwitchHdr { param($Policy, $ConfigPath, $ProfileName) }
        function script:Set-MonitorSwitchRefresh { param($ConfigPath, $ProfileName) }
        function script:Set-MonitorSwitchOsd { param($ConfigPath, $ProfileName) }
        function script:Invoke-MonitorSwitchInputVcp {
            param($Device, [int]$Target, [bool]$MayWrite)
            $panel = $script:wall | Where-Object Device -eq $Device
            if (-not $panel -or $panel.DisplayId -in $script:disabled) { throw "No DDC route to '$Device'." }
            if ($panel.DisplayId -in 3, 4) { throw 'An unconfigured left input was targeted.' }
            $cur = $script:panelInputs[$Device]
            $accepted = if ($MayWrite -and $cur -ne $Target) {
                if ($Device -ne $script:ignoreWritesFor) { $script:panelInputs[$Device] = $Target }
                $true
            }
            [pscustomobject]@{ Current = $cur; WriteAccepted = $accepted }
        }
        function script:Start-Sleep { param($Milliseconds) }

        Set-MonitorSwitchProfile left-middle -ConfigPath $Template -Confirm:$false
        Assert-Equal $script:disabled.Count 0
        Assert-Equal $script:panelInputs.gdi5 15
        Assert-Equal $script:panelInputs.gdi7 15

        Set-MonitorSwitchProfile left -ConfigPath $Template -Confirm:$false
        Assert-Equal (($script:disabled | Sort-Object) -join ',') '1,2'
        Assert-Equal $script:panelInputs.gdi5 17
        Assert-Equal $script:panelInputs.gdi7 17

        # The laptop or a person can change a panel even when Windows sees it as off.
        $script:panelInputs.gdi7 = 15
        Set-MonitorSwitchProfile left -ConfigPath $Template -Confirm:$false
        Assert-Equal (($script:disabled | Sort-Object) -join ',') '1,2'
        Assert-Equal $script:panelInputs.gdi7 17

        # A write acknowledged but ignored by a panel must not be reported as success.
        $script:ignoreWritesFor = 'gdi7'
        $script:panelInputs.gdi7 = 15
        $failure = $null
        try { Set-MonitorSwitchProfile left -ConfigPath $Template -Confirm:$false }
        catch { $failure = $_.Exception.Message }
        if (-not $failure -or $failure -notmatch 'not verified:.*top-middle -> HDMI1') {
            throw "Expected an unverified top-middle input, got: '$failure'."
        }
        Assert-Equal (($script:disabled | Sort-Object) -join ',') '1,2'

        $script:ignoreWritesFor = ''
        Set-MonitorSwitchProfile left-middle -ConfigPath $Template -WhatIf
        Assert-Equal (($script:disabled | Sort-Object) -join ',') '1,2'
        Set-MonitorSwitchProfile left-middle -ConfigPath $Template -SkipOsd -Confirm:$false
        Assert-Equal $script:disabled.Count 0
        Assert-Equal $script:panelInputs.gdi5 17
        Write-Host 'Input routing checks passed; no physical monitors were changed.' -ForegroundColor Green
    } (Join-Path $repo 'setups\home-pc\monitors.psd1')
}
finally { Remove-Module MonitorSwitch -Force }
