#Requires -Version 5.1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Module-local test doubles preserve production command signatures.')]
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$template = Join-Path $repo 'setups\home-pc\config.psd1'
$testState = Join-Path ([IO.Path]::GetTempPath()) ("monitor-switch-hdr-{0}" -f [guid]::NewGuid())
$module = Import-Module (Join-Path $repo 'src\Module\MonitorSwitch.psd1') -Force -PassThru

function Assert-Blocked {
    param([scriptblock]$Action, [string]$Pattern)
    $failure = $null
    try { & $Action | Out-Null }
    catch { $failure = $_ }
    if ($null -eq $failure -or $failure.Exception.Message -notmatch $Pattern) {
        throw "Expected a rejection matching '$Pattern', got: $failure"
    }
}

try {
    foreach ($scope in 'global', 'profile') {
        foreach ($field in 'policy', 'autoHdr') {
            foreach ($value in 'on', 'leave') {
                $hdr = "hdr = @{ policy = 'off'; autoHdr = 'off' }".Replace("$field = 'off'", "$field = '$value'")
                $globalHdr = if ($scope -eq 'global') { $hdr }
                $profileHdr = if ($scope -eq 'profile') { $hdr }
                $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("monitor-switch-hdr-{0}.psd1" -f [guid]::NewGuid())
                try {
                    [IO.File]::WriteAllText($fixture, "@{ layout=@{}; refresh=@{policy='safe'}; profiles=@{all=@{select='all'; $profileHdr}}; $globalHdr }")
                    Assert-Blocked { Get-MonitorSwitchConfig -Path $fixture } 'HDR is locked off'
                }
                finally {
                    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Force }
                }
            }
        }
    }
    foreach ($value in 'on', 'leave') {
        Assert-Blocked { Disable-MonitorSwitchHdr -Policy $value -WhatIf } 'parameter.*Policy'
        Assert-Blocked { Disable-MonitorSwitchHdr -AutoHdr $value -WhatIf } 'parameter.*AutoHdr'
    }
    Assert-Blocked { Disable-MonitorSwitchHdr -SdrNits 292 -WhatIf } 'parameter.*SdrNits'
    Assert-Blocked { Set-MonitorSwitchProfile all -SkipHdr -WhatIf } 'parameter.*SkipHdr'

    & $module {
        param($Template, $StateDir)
        $script:TestStateDir = $StateDir
        function script:Get-MonitorSwitchStateDir { $script:TestStateDir }

        function Assert-Equal {
            param($Actual, $Expected)
            if ($Actual -ne $Expected) { throw "Expected '$Expected', got '$Actual'." }
        }
        function Assert-Failure {
            param([scriptblock]$Action, [string]$Pattern)
            $failure = $null
            try { & $Action | Out-Null }
            catch { $failure = $_ }
            if ($null -eq $failure -or $failure.Exception.Message -notmatch $Pattern) {
                throw "Expected failure matching '$Pattern', got: $failure"
            }
        }

        $cfg = Get-MonitorSwitchConfig -Path $Template
        $geometry = @(
            [pscustomobject]@{ DisplayId = 1; X = 0; Y = -1440 }
            [pscustomobject]@{ DisplayId = 2; X = 0; Y = 0 }
            [pscustomobject]@{ DisplayId = 3; X = -3440; Y = 0 }
            [pscustomobject]@{ DisplayId = 4; X = -3440; Y = -1440 }
        )
        $grid = @(ConvertTo-MonitorSwitchGrid -Geometry $geometry -PanelWidth 3440 -PanelHeight 1440 `
            -ColumnNames $cfg.layout.columnNames -RowNames $cfg.layout.rowNames)
        Assert-Equal ($grid.Slot -join ',') 'top-middle,bottom-middle,bottom-left,top-left'
        $expected = @{ left = '3,4'; middle = '1,2'; 'left-middle' = '1,2,3,4'; 'top-left' = '4' }
        foreach ($name in $expected.Keys) {
            $keep = @(Resolve-MonitorSwitchSelection -Definition $cfg.profiles[$name] -Grid $grid)
            Assert-Equal (($keep | Sort-Object) -join ',') $expected[$name]
        }
        $singleGrid = @(ConvertTo-MonitorSwitchGrid -Geometry @($geometry[1]) -PanelWidth 3440 -PanelHeight 1440 `
            -ColumnNames $cfg.layout.columnNames -RowNames $cfg.layout.rowNames)
        Assert-Equal $singleGrid[0].Slot 'bottom-middle'

        $script:HdrState = @{ 1 = $true; 2 = $true }
        $script:AutoHdrState = $true
        $script:PlaybackState = $true
        $script:RegistryValue = 'AutoHDREnable=1;SwapEffectUpgradeEnable=1;VRROptimizeEnable=1;AutoHDREnable=1;'
        $script:Events = New-Object 'System.Collections.Generic.List[string]'
        $script:HdrFailure = $false
        $script:HdrSticksOn = $false
        $script:MissingHdrState = $false
        $script:AutoHdrSticksOn = $false
        $script:LayoutFailure = $false
        $script:RefreshFailure = $false
        $script:TopologyRenumbered = $false
        $script:TopologyDisconnected = $false
        $script:InactiveDisplay = $false
        $script:GridFailure = $false

        # All writes and display-state reads below are module-local test doubles.
        function script:Get-MonitorSwitchDisplayInfo {
            foreach ($id in 1, 2) {
                if ($script:TopologyDisconnected -and $id -eq 2) { continue }
                [pscustomobject]@{
                    DisplayId = if ($script:TopologyRenumbered) { 3 - $id } else { $id }
                    DevicePath = "test-display-$id"
                    Active = -not ($script:InactiveDisplay -and $id -eq 2)
                    Position = [pscustomobject]@{ X = 0; Y = 0 }
                    GdiDeviceName = "gdi$id"
                }
            }
        }
        function script:Get-MonitorSwitchGrid {
            param($Config, $Geometry)
            if ($script:GridFailure) { throw 'Slot labels are unavailable.' }
            foreach ($id in 1, 2) { [pscustomobject]@{ DisplayId = $id; Slot = "display-$id" } }
        }
        function script:Get-MonitorSwitchDisplayHdr {
            [CmdletBinding()]
            param([int[]]$DisplayId, [switch]$Global)
            if ($Global) {
                return [pscustomobject]@{ AutoHDREnabled = $script:AutoHdrState; HDRPlaybackEnabled = $script:PlaybackState }
            }
            foreach ($id in $DisplayId) {
                if ($script:MissingHdrState -and $id -eq 2) { continue }
                [pscustomobject]@{ DisplayId = $id; HDREnabled = $script:HdrState[$id] }
            }
        }
        function script:Disable-MonitorSwitchDisplayHdr {
            param([int[]]$DisplayId)
            if ($script:HdrFailure) { throw 'Display HDR write failed.' }
            if (-not $script:HdrSticksOn) {
                foreach ($id in $DisplayId) { $script:HdrState[$id] = $false }
            }
        }
        function script:Disable-MonitorSwitchHdrPlayback { $script:PlaybackState = $false }
        function script:Get-Item {
            [CmdletBinding()]
            param([string]$LiteralPath)
            $key = [pscustomobject]@{ Value = $script:RegistryValue }
            $key | Add-Member ScriptMethod GetValue { param($Name, $DefaultValue) $this.Value }
            $key | Add-Member ScriptMethod Dispose {}
            $key
        }
        function script:Test-Path {
            [CmdletBinding()]
            param([string]$LiteralPath, [Parameter(Position = 0)][string]$Path)
            $true
        }
        function script:New-ItemProperty {
            [CmdletBinding()]
            param([string]$LiteralPath, [string]$Name, [string]$PropertyType, [string]$Value, [switch]$Force)
            $script:RegistryValue = $Value
            $script:AutoHdrState = $script:AutoHdrSticksOn -or $Value -match 'AutoHDREnable=1;'
            $script:Events.Add('hdr')
        }
        function New-TestLayout {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Constructs an in-memory test object without external writes.')]
            [CmdletBinding()]
            param()
            $layout = [pscustomobject]@{ Available = [int[]]@(0, 1); DevicePaths = @('test-display-1', 'test-display-2') }
            $layout | Add-Member ScriptMethod GetGeometry {
                foreach ($id in 1, 2) {
                    [pscustomobject]@{ DisplayId = $id; DevicePath = "test-display-$id"; X = 0; Y = 0; Active = $true }
                }
            }
            $layout | Add-Member ScriptMethod Clone { New-TestLayout }
            $layout | Add-Member ScriptMethod PathsBase64 { 'AAAA' }
            $layout | Add-Member ScriptMethod ModesBase64 { 'AAAA' }
            $layout
        }
        function script:Read-MonitorSwitchSavedLayout { New-TestLayout }
        function script:Invoke-MonitorSwitchDesktopLayout {
            param($Layout)
            $script:Events.Add('layout')
            # Simulate Windows restoring the attached displays' remembered HDR state.
            foreach ($id in 1, 2) { $script:HdrState[$id] = $true }
            if ($script:LayoutFailure) { throw 'Layout apply failed.' }
        }
        function script:Invoke-MonitorSwitchRefreshPolicy {
            param($Settings, $Slots)
            $script:Events.Add('refresh')
            if ($script:RefreshFailure) { throw 'Refresh failed.' }
        }
        function script:Invoke-MonitorSwitchPicturePolicy {
            param($Settings, $Slots)
            $script:Events.Add('picture')
        }
        function script:Get-MonitorSwitchDesktopLayout {
            $script:Events.Add('capture')
            New-TestLayout
        }

        Disable-MonitorSwitchHdr -WhatIf
        Assert-Equal $script:Events.Count 0
        Assert-Equal $script:HdrState[1] $true
        Assert-Equal $script:AutoHdrState $true
        Assert-Equal $script:PlaybackState $true

        $script:GridFailure = $true
        Disable-MonitorSwitchHdr -Confirm:$false
        $script:GridFailure = $false
        Assert-Equal $script:HdrState[1] $false
        Assert-Equal $script:HdrState[2] $false
        Assert-Equal $script:AutoHdrState $false
        Assert-Equal $script:PlaybackState $false
        Assert-Equal $script:RegistryValue 'AutoHDREnable=0;SwapEffectUpgradeEnable=1;VRROptimizeEnable=1;'

        $script:HdrState[1] = $true
        $script:HdrFailure = $true
        Assert-Failure { Disable-MonitorSwitchHdr -Confirm:$false } 'Display HDR write failed'
        $script:HdrFailure = $false
        $script:HdrSticksOn = $true
        Assert-Failure { Disable-MonitorSwitchHdr -Confirm:$false } 'not off on every'
        $script:HdrSticksOn = $false
        $script:MissingHdrState = $true
        Assert-Failure { Disable-MonitorSwitchHdr -Confirm:$false } 'not returned for every'
        $script:MissingHdrState = $false
        $script:AutoHdrSticksOn = $true
        Assert-Failure { Disable-MonitorSwitchHdr -Confirm:$false } 'still enabled'
        $script:AutoHdrSticksOn = $false

        $script:Events.Clear()
        $script:TopologyRenumbered = $true
        Assert-Failure { Set-MonitorSwitchProfile all -ConfigPath $Template -WhatIf } 'numbering changed'
        $script:TopologyRenumbered = $false
        $script:TopologyDisconnected = $true
        Assert-Failure { Set-MonitorSwitchProfile all -ConfigPath $Template -WhatIf } 'Connected monitors changed'
        $script:TopologyDisconnected = $false
        $script:InactiveDisplay = $true
        Assert-Failure { Save-MonitorSwitchLayout -ConfigPath $Template -Confirm:$false } 'Enable every connected display'
        $script:InactiveDisplay = $false
        Assert-Equal $script:Events.Count 0

        $script:Events.Clear()
        Set-MonitorSwitchProfile all -ConfigPath $Template -Confirm:$false
        Assert-Equal ($script:Events -join ',') 'hdr,layout,hdr,refresh,picture'
        Assert-Equal $script:HdrState[1] $false
        Assert-Equal $script:HdrState[2] $false

        $script:Events.Clear()
        $script:LayoutFailure = $true
        Assert-Failure { Set-MonitorSwitchProfile all -ConfigPath $Template -Confirm:$false } 'Layout apply failed'
        Assert-Equal ($script:Events -join ',') 'hdr,layout,hdr'
        Assert-Equal $script:HdrState[1] $false
        Assert-Equal $script:HdrState[2] $false
        $script:LayoutFailure = $false

        $script:Events.Clear()
        $script:RefreshFailure = $true
        Assert-Failure { Set-MonitorSwitchProfile all -ConfigPath $Template -Confirm:$false } 'Refresh failed'
        Assert-Equal ($script:Events -join ',') 'hdr,layout,hdr,refresh'
        Assert-Equal $script:HdrState[1] $false
        $script:RefreshFailure = $false

        $script:Events.Clear()
        Save-MonitorSwitchLayout -ConfigPath $Template -WhatIf
        Assert-Equal $script:Events.Count 0
        Save-MonitorSwitchLayout -ConfigPath $Template -Confirm:$false
        Assert-Equal ($script:Events -join ',') 'hdr,capture'
    } $template $testState

    Write-Host 'HDR lockout checks passed; no real display or registry settings were changed.' -ForegroundColor Green
}
finally {
    Remove-Module MonitorSwitch -Force
    if ([IO.Directory]::Exists($testState)) { [IO.Directory]::Delete($testState, $true) }
}
