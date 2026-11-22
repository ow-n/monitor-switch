#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
    throw 'MonitorSwitch requires Windows.'
}

$sourceRoot = Split-Path -Parent $PSScriptRoot
$script:RepositoryRoot = Split-Path -Parent $sourceRoot
$script:MonitorSwitchSetup = ''
foreach ($file in @(
    'Windows\DisplayTopology.ps1'
    'Windows\DisplayModes.ps1'
    'Windows\MonitorConnection.ps1'
    'MonitorControl\InputSelection.ps1'
    'Configuration\SetupConfiguration.ps1'
    'Layout\SavedLayout.ps1'
    'Layout\ProfileSets.ps1'
    'Layout\SetLayout.ps1'
    'Layout\MonitorSlots.ps1'
    'MonitorControl\RefreshRatePolicy.ps1'
    'MonitorControl\PictureSettings.ps1'
    'Layout\ProfileOperations.ps1'
    'Diagnostics\DisplayDiagnostics.ps1'
)) {
    $path = Join-Path $sourceRoot $file
    if (-not [IO.File]::Exists($path)) { throw "Required module file '$file' is missing." }
    . $path
}

$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'MonitorSwitch.psd1')
foreach ($name in $manifest.FunctionsToExport) {
    if (-not (Test-Path -LiteralPath "Function:\$name")) { throw "Module command '$name' was not loaded." }
}
Export-ModuleMember -Function $manifest.FunctionsToExport
