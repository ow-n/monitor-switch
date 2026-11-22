#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$pwsh = Join-Path $PSHOME 'pwsh.exe'
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("monitor switch {0}" -f [guid]::NewGuid())
$local = $env:LOCALAPPDATA
$modules = $env:PSModulePath
try {
    [void][IO.Directory]::CreateDirectory($sandbox)
    foreach ($dir in 'src', 'scripts') { Copy-Item -LiteralPath (Join-Path $repo $dir) -Destination $sandbox -Recurse }
    foreach ($setup in 'home-pc', 'home-laptop', 'office-laptop') {
        $source = Join-Path $repo "setups\$setup"
        $dest = Join-Path $sandbox "setups\$setup"
        [void][IO.Directory]::CreateDirectory($dest)
        Get-ChildItem -LiteralPath $source -File | Copy-Item -Destination $dest
    }
    $env:LOCALAPPDATA = Join-Path $sandbox 'empty-appdata'
    $env:PSModulePath = Join-Path $PSHOME 'Modules'
    $cli = Join-Path $sandbox 'scripts\monitor-switch.ps1'
    foreach ($setup in 'home-pc', 'home-laptop', 'office-laptop') {
        $output = & $pwsh -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File $cli config -Setup $setup
        $expected = Join-Path $sandbox "setups\$setup\config.psd1"
        if ($LASTEXITCODE -ne 0 -or "$output" -ne $expected) { throw "Fresh checkout: expected $expected; got $output" }
    }
    $all = Join-Path $sandbox 'setups\home-laptop\ALL.bat'
    $output = & $env:ComSpec /d /c "call `"$all`" <nul"
    if ($LASTEXITCODE -ne 1 -or "$output" -notlike '*scripts\monitor-switch.ps1 capture -Setup home-laptop*') {
        throw "ALL without a capture should fail with the location-specific next step: $output"
    }
    if (Test-Path -LiteralPath (Join-Path $sandbox 'state')) { throw 'Uncaptured ALL created state.' }

    # The native refresh seam is synthetic; the profile and cap policy remain real.
    Add-Type -TypeDefinition @'
using System.Collections.Generic;
namespace MonitorSwitch.Windows {
  public class TestDisplayMode {
    public string Device, Monitor;
    public int X, Y;
    public uint Width = 1920, Height = 1080, Bpp = 32, Current;
    public uint[] Available = new uint[] { 30, 60, 120, 144 };
  }
  public static class DisplayModes {
    public static int Writes;
    public static uint LastHz;
    public static string LastDevice;
    public static bool RequestedSupportedModes;
    public static List<TestDisplayMode> Query(bool includeSupportedRates) {
      RequestedSupportedModes = includeSupportedRates;
      return new List<TestDisplayMode> {
        new TestDisplayMode { Device = @"\\.\DISPLAY1", Monitor = "test-panel-1", Current = 144 },
        new TestDisplayMode { Device = @"\\.\DISPLAY2", Monitor = "test-panel-2", X = 1920, Current = 30 }
      };
    }
    public static int SetRefresh(string device, uint hz) {
      Writes++; LastDevice = device; LastHz = hz; return 0;
    }
  }
}
'@
    # Real serialization and profile operations; only Windows discovery and writes are synthetic.
    $module = Import-Module (Join-Path $sandbox 'src\Module\MonitorSwitch.psd1') -Force -PassThru
    & $module {
        $script:PanelPrefix = ''
        $script:WindowsWrites = 0
        $script:CaptureFailure = $false
        function script:Get-MonitorSwitchDisplayInfo {
            foreach ($id in 1, 2) {
                [pscustomobject]@{
                    DisplayId = $id; DevicePath = "$script:PanelPrefix-panel-$id"
                    Active = $true; Position = @{ X = 1920 * ($id - 1); Y = 0 }
                    GdiDeviceName = "\\.\DISPLAY$id"
                    Primary = $id -eq 1; ConnectionType = 'Other'; Width = 1920; Height = 1080
                }
            }
        }
        function script:Disable-MonitorSwitchHdr { $script:WindowsWrites++ }
        function script:Get-MonitorSwitchDesktopLayout {
            if ($script:CaptureFailure) { throw 'Capture query failed.' }
            $layout = [MonitorSwitch.Windows.DesktopLayout]::new()
            $paths = @()
            $modes = @()
            foreach ($index in 0, 1) {
                $position = [MonitorSwitch.Windows.POINTL]::new()
                $position.x = 1920 * $index
                $sourceMode = [MonitorSwitch.Windows.SOURCE_MODE]::new()
                $sourceMode.width = 1920; $sourceMode.height = 1080; $sourceMode.pixelFormat = 4
                $sourceMode.position = $position
                $mode = [MonitorSwitch.Windows.MODE_INFO]::new()
                $mode.infoType = 1; $mode.id = $index; $mode.sourceMode = $sourceMode
                $modes += $mode
                $source = [MonitorSwitch.Windows.PATH_SOURCE_INFO]::new()
                $source.id = $index; $source.modeInfoIdx = $index
                $target = [MonitorSwitch.Windows.PATH_TARGET_INFO]::new()
                $target.id = $index; $target.targetAvailable = 1; $target.rotation = 1
                $path = [MonitorSwitch.Windows.PATH_INFO]::new()
                $path.sourceInfo = $source; $path.targetInfo = $target; $path.flags = 1
                $paths += $path
            }
            $layout.Paths = [MonitorSwitch.Windows.PATH_INFO[]]$paths
            $layout.Modes = [MonitorSwitch.Windows.MODE_INFO[]]$modes
            $layout.Available = [int[]]@(0, 1)
            $layout.DevicePaths = [string[]]@("$script:PanelPrefix-panel-1", "$script:PanelPrefix-panel-2")
            $layout
        }
        function script:Invoke-MonitorSwitchDesktopLayout {
            param($Layout)
            $script:WindowsWrites++
            $script:applied = @($Layout.GetGeometry())
        }
    }
    foreach ($setup in 'home-laptop', 'office-laptop') {
        Set-MonitorSwitchSetup -Name $setup
        & $module { param($Label) $script:PanelPrefix = $Label } $setup
        Save-MonitorSwitchLayout -Confirm:$false
        $captureFiles = @(Get-ChildItem -LiteralPath (Join-Path $sandbox "state\$setup") -File)
        if ($captureFiles.Count -ne 1 -or $captureFiles[0].Name -ne 'layout.json') {
            throw "Capture must write one authoritative layout.json for $setup, got: $($captureFiles.Name -join ', ')"
        }
    }
    foreach ($setup in 'office-laptop', 'home-laptop') {
        Set-MonitorSwitchSetup -Name $setup
        & $module { param($Label) $script:PanelPrefix = $Label } $setup
        Set-MonitorSwitchProfile all -Confirm:$false
        $identities = & $module { $script:applied.DevicePath -join ',' }
        $positions = & $module { $script:applied.X -join ',' }
        if ($identities -ne "$setup-panel-1,$setup-panel-2" -or $positions -ne '0,1920') {
            throw "Wrong saved layout applied for ${setup}: $identities at $positions"
        }
    }
    Set-MonitorSwitchSetup -Name home-pc
    $oldState = Join-Path $sandbox 'state\home-pc'
    [void][IO.Directory]::CreateDirectory($oldState)
    [IO.File]::WriteAllText((Join-Path $oldState 'baseline.json'), '{}')
    [IO.File]::WriteAllText((Join-Path $oldState 'positions.json'), '[]')
    $failure = $null
    try { Set-MonitorSwitchProfile all -WhatIf } catch { $failure = $_.Exception.Message }
    if ($failure -notlike '*No saved layout*') { throw "PC setup must not inherit laptop state: $failure" }

    Set-MonitorSwitchSetup -Name home-laptop
    & $module { $script:PanelPrefix = 'home-laptop' }
    $savedPath = Join-Path $sandbox 'state\home-laptop\layout.json'
    $valid = [IO.File]::ReadAllText($savedPath)
    foreach ($case in 'version', 'payload', 'index') {
        $invalid = ConvertFrom-Json -InputObject $valid
        $pattern = switch ($case) {
            'version' { $invalid.Version = 2; 'Unsupported saved layout' }
            'payload' { $invalid.Paths = 'AAAA'; 'Snapshot data is corrupt' }
            'index' { $invalid.Displays[0].PathIndex = 99; 'path indexes are invalid' }
        }
        $writes = & $module { $script:WindowsWrites }
        try {
            [IO.File]::WriteAllText($savedPath, ($invalid | ConvertTo-Json -Depth 5))
            $failure = $null
            try { Set-MonitorSwitchProfile all -Confirm:$false } catch { $failure = $_.Exception.Message }
            if ($failure -notmatch $pattern -or (& $module { $script:WindowsWrites }) -ne $writes) {
                throw "Invalid $case capture was not blocked before Windows writes: $failure"
            }
        }
        finally { [IO.File]::WriteAllText($savedPath, $valid) }
    }
    & $module { $script:CaptureFailure = $true }
    $failure = $null
    try { Save-MonitorSwitchLayout -Confirm:$false } catch { $failure = $_.Exception.Message }
    & $module { $script:CaptureFailure = $false }
    if ($failure -notmatch 'Capture query failed' -or [IO.File]::ReadAllText($savedPath) -ne $valid) {
        throw 'A failed capture replaced the working saved layout.'
    }
    Save-MonitorSwitchLayout -Confirm:$false
    if (@(Get-ChildItem -LiteralPath (Split-Path -Parent $savedPath) -File).Count -ne 1) {
        throw 'Replacing a capture left redundant state or temporary files.'
    }
    $capConfig = Join-Path $sandbox 'cap-policy.psd1'
    [IO.File]::WriteAllText($capConfig, "@{ layout=@{panelWidth=1920;panelHeight=1080}; refresh=@{policy='safe';safeHz=60}; picture=@{policy='leave'}; profiles=@{all=@{select='all'}} }")
    Set-MonitorSwitchProfile all -ConfigPath $capConfig -Confirm:$false
    if ([MonitorSwitch.Windows.DisplayModes]::Writes -ne 1 -or
        [MonitorSwitch.Windows.DisplayModes]::LastDevice -ne '\\.\DISPLAY1' -or
        [MonitorSwitch.Windows.DisplayModes]::LastHz -ne 60 -or
        -not [MonitorSwitch.Windows.DisplayModes]::RequestedSupportedModes) {
        throw 'ALL must lower 144 Hz to the 60 Hz cap without raising the display already at 30 Hz.'
    }
    Set-MonitorSwitchProfile all -ConfigPath $capConfig -WhatIf
    if ([MonitorSwitch.Windows.DisplayModes]::Writes -ne 1) { throw 'A dry-run ALL wrote a refresh rate.' }
    Remove-Module $module

    # Stand in for the CLI only in the relocated copy: exercise the actual Explorer entry points
    # from an unrelated working directory without applying any display or registry changes.
    [IO.File]::WriteAllText($cli, @'
param([string]$Command, [string]$Name, [string]$Setup, [switch]$WhatIf)
"$Setup|$Command|$Name|$WhatIf"
'@)
    $actions = @{
        'home-pc' = @('all', 'left', 'left-middle', 'top-left')
        'home-laptop' = @('all', 'right', 'center-right', 'top-right')
        'office-laptop' = @('capture', 'all')
    }
    foreach ($setup in $actions.Keys) {
        foreach ($action in $actions[$setup]) {
            $launcherName = if ($setup -eq 'home-pc' -and $action -eq 'left-middle') { 'LEFT + MIDDLE' }
            elseif ($setup -eq 'home-laptop' -and $action -eq 'center-right') { 'RIGHT + MIDDLE' } else { $action }
            $launcher = Join-Path $sandbox "setups\$setup\$launcherName.bat"
            if (-not (Test-Path -LiteralPath $launcher)) { throw "Missing clickable launcher: $setup\$launcherName.bat" }
            $operation = if ($action -eq 'capture') { "$action|" } else { "switch|$action" }
            $output = & $env:ComSpec /d /c "call `"$launcher`" -WhatIf <nul"
            if ($LASTEXITCODE -ne 0 -or "$output" -ne "$setup|$operation|True") {
                throw "Wrong dispatch from $launcher : $output (exit $LASTEXITCODE)"
            }
        }
    }
    Write-Host 'Portable setup, launcher, and isolated capture/ALL checks passed.'
}
finally {
    if (Get-Module MonitorSwitch | Where-Object { $_.ModuleBase.StartsWith($sandbox) }) { Remove-Module MonitorSwitch }
    $env:LOCALAPPDATA = $local
    $env:PSModulePath = $modules
    if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
