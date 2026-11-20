#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$originalLocalAppData = $env:LOCALAPPDATA
$originalOverride = $env:MONITOR_SWITCH_CONFIG
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("monitor-switch-setups-{0}" -f [guid]::NewGuid())
$modulePath = Join-Path $repo 'src\MonitorSwitch\MonitorSwitch.psd1'

function Assert-Equal {
    param($Actual, $Expected)
    if ($Actual -ne $Expected) { throw "Expected '$Expected', got '$Actual'." }
}

function Assert-Blocked {
    param([scriptblock]$Action, [string]$Pattern)
    $failure = $null
    try { & $Action | Out-Null }
    catch { $failure = $_ }
    if ($null -eq $failure -or $failure.Exception.Message -notmatch $Pattern) {
        throw "Expected failure matching '$Pattern', got: $failure"
    }
}

try {
    $env:LOCALAPPDATA = $sandbox
    $env:MONITOR_SWITCH_CONFIG = $null
    New-Item -ItemType Directory -Path $sandbox | Out-Null
    $module = Import-Module $modulePath -Force -PassThru
    Assert-Blocked { Get-MonitorSwitchConfig } 'Choose a setup'
    Assert-Blocked { & (Join-Path $repo 'install.ps1') -SkipCapture -NoShortcuts } 'Choose -Setup'
    Assert-Blocked { Set-MonitorSwitchSetup -Name '..\home-pc' } 'does not match'
    Assert-Blocked { Set-MonitorSwitchSetup -Name 'unknown' } 'Unknown setup'

    foreach ($setup in 'home-pc', 'home-laptop', 'office-laptop') {
        & (Join-Path $repo 'install.ps1') -Setup $setup -SkipCapture -NoShortcuts
        $module = Get-Module MonitorSwitch
        $expectedDir = Join-Path $sandbox "MonitorSwitch\setups\$setup"
        $configPath = Join-Path $expectedDir 'monitors.yaml'
        Assert-Equal ((Get-MonitorSwitchConfig)['_path']) $configPath

        # A legacy override must not redirect an explicitly selected setup.
        $env:MONITOR_SWITCH_CONFIG = Join-Path $sandbox 'unrelated-missing.yaml'
        Assert-Equal ((Get-MonitorSwitchConfig)['_path']) $configPath
        $state = & $module { Get-MonitorSwitchStateDir }
        Assert-Equal $state (Join-Path $expectedDir 'state')
        Assert-Equal (& $module { Test-MonitorSwitchBaseline }) $false
        Assert-Blocked { & $module { Import-MonitorSwitchBaselineConfig } } 'No baseline snapshot'
        $cli = Join-Path $repo 'bin\monitor-switch.ps1'
        $output = & pwsh -NoProfile -File $cli config -Setup $setup
        Assert-Equal $LASTEXITCODE 0
        Assert-Equal $output $configPath
        $output = & pwsh -NoProfile -File $cli restore -Setup $setup
        Assert-Equal $LASTEXITCODE 1
        if (($output -join "`n") -notmatch 'No baseline snapshot') {
            throw "Restore for uncaptured setup $setup did not fail before applying a layout: $output"
        }
        # GitHub Actions propagates LASTEXITCODE, including this expected failure.
        $global:LASTEXITCODE = 0
        [System.IO.File]::WriteAllText((Join-Path $state 'baseline.json'), $setup)

        $shortcutDir = Join-Path $sandbox "$setup launchers"
        New-MonitorSwitchShortcut -Directory $shortcutDir -ConfigPath $configPath
        $launcher = Get-Content -LiteralPath (Join-Path $shortcutDir 'ALL.bat') -Raw
        if (-not $launcher.Contains("-Setup `"$setup`"") -or -not $launcher.Contains("-ConfigPath `"$configPath`"")) {
            throw "Launcher for $setup did not pin its setup and config."
        }
    }

    $module = Get-Module MonitorSwitch
    & $module {
        function script:Import-MonitorSwitchSnapshot {
            param([string]$Path)
            Get-Content -LiteralPath $Path -Raw
        }
        function script:Get-MonitorSwitchGrid { throw 'Alignment must not use home grid selectors.' }
    }
    foreach ($setup in 'home-pc', 'home-laptop', 'office-laptop') {
        Set-MonitorSwitchSetup -Name $setup
        Assert-Equal (& $module { Import-MonitorSwitchBaselineConfig }) $setup
    }
    foreach ($setup in 'home-laptop', 'office-laptop') {
        Set-MonitorSwitchSetup -Name $setup
        $cfg = Get-MonitorSwitchConfig
        Assert-Equal $cfg.mode 'alignment'
        Assert-Equal $cfg.refresh.policy 'native'
        Assert-Equal (@(Get-MonitorSwitchProfile).Keeps) 'all (full restore)'
    }

    $cfg = Get-MonitorSwitchConfig -Path (Join-Path $repo 'setups\home-pc\monitors.yaml')
    [void]$cfg.Remove('_path')
    $cfg.mode = 'alignment'
    $fixture = Join-Path $sandbox 'unsafe-alignment.yaml'
    [System.IO.File]::WriteAllText($fixture, (ConvertTo-Yaml $cfg))
    Assert-Blocked { Get-MonitorSwitchConfig -Path $fixture } 'Alignment-only setups cannot disable'

    # Existing unqualified home launchers keep their original config/state.
    Remove-Module MonitorSwitch -Force
    $module = Import-Module $modulePath -Force -PassThru
    $env:MONITOR_SWITCH_CONFIG = $null
    $legacyDir = Join-Path $sandbox 'MonitorSwitch'
    Copy-Item (Join-Path $repo 'monitors.yaml') (Join-Path $legacyDir 'monitors.yaml')
    Assert-Equal ((Get-MonitorSwitchConfig)['_path']) (Join-Path $legacyDir 'monitors.yaml')
    Assert-Equal (& $module { Get-MonitorSwitchStateDir }) (Join-Path $legacyDir 'state')
    Assert-Equal (& $module { Test-MonitorSwitchBaseline }) $false

    Write-Host 'Setup isolation checks passed; no display or registry settings were changed.' -ForegroundColor Green
}
finally {
    Remove-Module MonitorSwitch -Force -ErrorAction SilentlyContinue
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:MONITOR_SWITCH_CONFIG = $originalOverride
    if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
