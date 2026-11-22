#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$winps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("monitor switch {0}" -f [guid]::NewGuid())
$local = $env:LOCALAPPDATA
$modules = $env:PSModulePath
try {
    [void][IO.Directory]::CreateDirectory($sandbox)
    foreach ($dir in 'src', 'bin', 'config') { Copy-Item -LiteralPath (Join-Path $repo $dir) -Destination $sandbox -Recurse }
    foreach ($setup in 'home-pc', 'home-laptop', 'office-laptop') {
        $source = Join-Path $repo "setups\$setup"
        $dest = Join-Path $sandbox "setups\$setup"
        [void][IO.Directory]::CreateDirectory($dest)
        Get-ChildItem -LiteralPath $source -File | Copy-Item -Destination $dest
    }
    $env:LOCALAPPDATA = Join-Path $sandbox 'empty-appdata'
    $env:PSModulePath = Join-Path (Split-Path -Parent $winps) 'Modules'
    $cli = Join-Path $sandbox 'bin\monitor-switch.ps1'
    foreach ($setup in 'home-pc', 'home-laptop', 'office-laptop') {
        $output = & $winps -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File $cli config -Setup $setup
        $expected = Join-Path $sandbox "config\$setup.psd1"
        if ($LASTEXITCODE -ne 0 -or "$output" -ne $expected) { throw "Fresh checkout: expected $expected; got $output" }
    }
    $restore = Join-Path $sandbox 'setups\home-laptop\RESTORE.bat'
    $output = & $env:ComSpec /d /c "call `"$restore`" <nul"
    if ($LASTEXITCODE -ne 1 -or "$output" -notlike '*home-laptop\CAPTURE.bat*') {
        throw "Restore without a capture should fail with the location-specific next step: $output"
    }
    if (Test-Path -LiteralPath (Join-Path $sandbox 'state')) { throw 'An uncaptured restore created state.' }

    # Save and restore *local* snapshots through the public API. Only the hardware layer is synthetic.
    $module = Import-Module (Join-Path $sandbox 'src\MonitorSwitch\MonitorSwitch.psd1') -Force -PassThru
    & $module {
        function script:Get-MonitorSwitchDisplayInfo {
            foreach ($id in 1, 2) {
                [pscustomobject]@{ DisplayId = $id; DevicePath = "test-panel-$id"; Active = $true; Position = @{ X = 1920 * ($id - 1); Y = 0 } }
            }
        }
        function script:Set-MonitorSwitchHdr {}
        function script:Set-MonitorSwitchRefresh {}
        function script:Set-MonitorSwitchOsd {}
        function script:Export-MonitorSwitchBaselineConfig { param($Path) [IO.File]::WriteAllText($Path, $script:snapshot) }
        function script:Import-MonitorSwitchSnapshot { param($Path) [IO.File]::ReadAllText($Path) }
        function script:Invoke-MonitorSwitchLayout { param($Config) $script:applied = $Config }
    }
    foreach ($setup in 'home-laptop', 'office-laptop') {
        Set-MonitorSwitchSetup -Name $setup
        & $module { param($Label) $script:snapshot = $Label } "captured-$setup"
        Save-MonitorSwitchBaseline -Confirm:$false
    }
    foreach ($setup in 'office-laptop', 'home-laptop') {
        Set-MonitorSwitchSetup -Name $setup
        Set-MonitorSwitchProfile all -Confirm:$false
        if ((& $module { $script:applied }) -ne "captured-$setup") { throw "Wrong baseline restored for $setup." }
    }
    Set-MonitorSwitchSetup -Name home-pc
    $failure = $null
    try { Set-MonitorSwitchProfile all -WhatIf } catch { $failure = $_.Exception.Message }
    if ($failure -notlike '*No baseline snapshot*') { throw "PC setup must not inherit laptop state: $failure" }
    Remove-Module $module

    # Stand in for the CLI only in the relocated copy: exercise the actual Explorer entry points
    # from an unrelated working directory without applying any display or registry changes.
    [IO.File]::WriteAllText($cli, @'
param([string]$Command, [string]$Name, [string]$Setup, [switch]$WhatIf)
"$Setup|$Command|$Name|$WhatIf"
'@)
    $actions = @{
        'home-pc' = @('all', 'left', 'left-middle', 'top-left')
        'home-laptop' = @('capture', 'restore')
        'office-laptop' = @('capture', 'restore')
    }
    foreach ($setup in $actions.Keys) {
        foreach ($action in $actions[$setup]) {
            $launcherName = if ($setup -eq 'home-pc' -and $action -eq 'left-middle') { 'LEFT + MIDDLE' } else { $action }
            $launcher = Join-Path $sandbox "setups\$setup\$launcherName.bat"
            if (-not (Test-Path -LiteralPath $launcher)) { throw "Missing clickable launcher: $setup\$launcherName.bat" }
            $operation = if ($action -in 'capture', 'restore') { "$action|" } else { "switch|$action" }
            $output = & $env:ComSpec /d /c "call `"$launcher`" -WhatIf <nul"
            if ($LASTEXITCODE -ne 0 -or "$output" -ne "$setup|$operation|True") {
                throw "Wrong dispatch from $launcher : $output (exit $LASTEXITCODE)"
            }
        }
    }
    Write-Host 'Portable setup, launcher, and isolated capture/restore checks passed.'
}
finally {
    if (Get-Module MonitorSwitch | Where-Object { $_.ModuleBase.StartsWith($sandbox) }) { Remove-Module MonitorSwitch }
    $env:LOCALAPPDATA = $local
    $env:PSModulePath = $modules
    if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
