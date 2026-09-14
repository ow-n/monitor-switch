#Requires -Version 5.1
<#
.SYNOPSIS
    Install Monitor Switch dependencies, seed a per-machine config, and capture a baseline.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -SkipCapture
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$SkipCapture,
    [switch]$NoShortcuts
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

Write-Host "`nMonitor Switch installer" -ForegroundColor Cyan

# --- 1. Dependencies ---------------------------------------------------------
$deps = @{ 'DisplayConfig' = '6.0.0'; 'powershell-yaml' = '0.4.7' }
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
$dataDir  = Join-Path $env:LOCALAPPDATA 'MonitorSwitch'
$userCfg  = Join-Path $dataDir 'monitors.yaml'
$template = Join-Path $root 'monitors.yaml'

if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
if (Test-Path $userCfg) {
    Write-Host "  [ok]   config already at $userCfg" -ForegroundColor DarkGray
}
elseif ($PSCmdlet.ShouldProcess($userCfg, 'seed config from template')) {
    Copy-Item $template $userCfg
    Write-Host "  [new]  $userCfg" -ForegroundColor Green
}

# --- 3. Baseline snapshot ----------------------------------------------------
Import-Module DisplayConfig -ErrorAction Stop
Import-Module (Join-Path $root 'src\MonitorSwitch\MonitorSwitch.psd1') -Force -ErrorAction Stop

$baseline = Join-Path $dataDir 'state\baseline.xml'
if ($SkipCapture) {
    Write-Host '  [skip] baseline capture' -ForegroundColor DarkGray
}
elseif (Test-Path $baseline) {
    Write-Host "  [ok]   baseline already captured" -ForegroundColor DarkGray
}
else {
    Write-Host "`n  Arrange every monitor the way you want it, then confirm." -ForegroundColor Yellow
    Save-MonitorSwitchBaseline
}

# --- 4. Shortcuts ------------------------------------------------------------
if (-not $NoShortcuts) {
    Write-Host "`nGenerating shortcuts" -ForegroundColor Cyan
    New-MonitorSwitchShortcut
}

Write-Host "`nDone. Try:" -ForegroundColor Green
Write-Host "  .\bin\monitor-switch.ps1 status"
Write-Host "  .\bin\monitor-switch.ps1 list"
Write-Host "  .\bin\monitor-switch.ps1 switch left`n"
