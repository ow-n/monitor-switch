#Requires -Version 5.1
<#
.SYNOPSIS
    Install Monitor Switch dependencies, seed a per-machine config, and capture a baseline.

.EXAMPLE
    .\install.ps1 -Setup home-pc
    .\install.ps1 -Setup office-laptop -SkipCapture
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$SkipCapture,
    [switch]$NoShortcuts,
    [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
    [string]$Setup
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dataDir = Join-Path $env:LOCALAPPDATA 'MonitorSwitch'
$template = Join-Path $root 'monitors.yaml'
if ($Setup) {
    $template = Join-Path $root "setups\$Setup\monitors.yaml"
    if (-not (Test-Path -LiteralPath $template)) { throw "Unknown setup '$Setup'." }
    $dataDir = Join-Path $dataDir "setups\$Setup"
}
elseif (-not (Test-Path -LiteralPath (Join-Path $dataDir 'monitors.yaml'))) {
    throw 'Choose -Setup home-pc, home-laptop, or office-laptop. A new machine must not inherit the home PC layout.'
}
$userCfg = Join-Path $dataDir 'monitors.yaml'

Write-Host "`nMonitor Switch installer" -ForegroundColor Cyan

# --- 1. Dependencies ---------------------------------------------------------
$deps = @{ 'powershell-yaml' = '0.4.7' }
foreach ($name in $deps.Keys) {
    $have = Get-Module -ListAvailable $name |
        Where-Object { $_.Version -ge [version]$deps[$name] } | Select-Object -First 1
    if ($have) {
        Write-Host "  [ok]   $name $($have.Version)" -ForegroundColor DarkGray
        continue
    }
    if ($PSCmdlet.ShouldProcess($name, 'Install-Module')) {
        Write-Host "  [get]  $name" -ForegroundColor Yellow
        Install-Module $name -Scope CurrentUser -Force -AllowClobber -MinimumVersion $deps[$name]
    }
}

# --- 2. Per-machine config ---------------------------------------------------
# The repo copy stays pristine so `git pull` never clobbers local tuning.
if (Test-Path $userCfg) {
    Write-Host "  [ok]   config already at $userCfg" -ForegroundColor DarkGray
}
elseif ($PSCmdlet.ShouldProcess($userCfg, 'seed config from template')) {
    if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
    Copy-Item $template $userCfg
    Write-Host "  [new]  $userCfg" -ForegroundColor Green
}

# --- 3. Baseline snapshot ----------------------------------------------------
Import-Module (Join-Path $root 'src\MonitorSwitch\MonitorSwitch.psd1') -Force -ErrorAction Stop
if ($Setup) { Set-MonitorSwitchSetup -Name $Setup }
$configPath = if (Test-Path -LiteralPath $userCfg) { $userCfg } else { $template }

$baseline = Join-Path $dataDir 'state\baseline.json'
if ($SkipCapture) {
    Write-Host '  [skip] baseline capture' -ForegroundColor DarkGray
}
elseif ((Test-Path $baseline) -or (Test-Path (Join-Path $dataDir 'state\baseline.xml'))) {
    Write-Host "  [ok]   baseline already captured" -ForegroundColor DarkGray
}
else {
    Write-Host "`n  Arrange every monitor the way you want it, then confirm." -ForegroundColor Yellow
    Save-MonitorSwitchBaseline -ConfigPath $configPath
}

# --- 4. Shortcuts ------------------------------------------------------------
if (-not $NoShortcuts) {
    Write-Host "`nGenerating shortcuts" -ForegroundColor Cyan
    New-MonitorSwitchShortcut -ConfigPath $configPath
}

Write-Host "`nDone. Try:" -ForegroundColor Green
$context = if ($Setup) { " -Setup $Setup" } else { '' }
Write-Host "  .\bin\monitor-switch.ps1 status$context"
Write-Host "  .\bin\monitor-switch.ps1 list$context"
Write-Host "  .\bin\monitor-switch.ps1 restore$context`n"
