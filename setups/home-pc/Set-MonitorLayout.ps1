#Requires -Version 5.1
<#
  Re-map the captured, connected panels by physical slot, never by DisplayId.
  Target grid (top-right slot is empty):

        top-left / 180  top-middle / 180  (none)

        bottom-left     bottom-middle    bottom-right
                        (primary)

  Only the top row is mounted inverted. Missing slots are left disconnected.
#>
[CmdletBinding()]
param(
    [ValidateSet('home-pc')]
    [string]$Setup = 'home-pc'
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\..\src\MonitorSwitch\MonitorSwitch.psd1'
Import-Module $modulePath -Force -ErrorAction Stop
Set-MonitorSwitchSetup -Name $Setup
$mod = Get-Module MonitorSwitch
& $mod { Assert-MonitorSwitchTopology }
Set-MonitorSwitchHdr -Policy off

$W = 3440
$H = 1440

$slots = @{
    'top-left'      = @{ Rotation = 'Rotate180'; X = -$W; Y = -$H }
    'top-middle'    = @{ Rotation = 'Rotate180'; X = 0; Y = -$H }
    'bottom-left'   = @{ Rotation = 'None'; X = -$W; Y = 0 }
    'bottom-middle' = @{ Rotation = 'None'; X = 0; Y = 0 }
    'bottom-right'  = @{ Rotation = 'None'; X = $W; Y = 0 }
}
$liveSlots = @(Get-MonitorSwitchStatus)
if (@($liveSlots | Where-Object State -ne 'Active').Count -gt 0) {
    throw 'Restore all connected displays before applying the full physical layout.'
}
$target = @(foreach ($display in $liveSlots) {
    if (-not $slots.ContainsKey($display.Slot)) { throw "Unknown physical slot '$($display.Slot)'." }
    $slot = $slots[$display.Slot]
    [pscustomobject]@{ Id = $display.DisplayId; Slot = $display.Slot; Rotation = $slot.Rotation; X = $slot.X; Y = $slot.Y }
})
$primary = @($target | Where-Object Slot -eq 'bottom-middle')
if ($primary.Count -ne 1) { throw 'Exactly one bottom-middle display is required for this layout.' }
$primaryId = $primary[0].Id

function Show-Layout {
    param([string]$Title)
    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
    & $mod { Get-MonitorSwitchDisplayInfo } | Where-Object Active |
        Select-Object DisplayId, Rotation, Position, ConnectionType |
        Sort-Object DisplayId | Format-Table -AutoSize
}

Show-Layout 'BEFORE'

# --- Backup -----------------------------------------------------------------
$stateDir = & $mod { Get-MonitorSwitchStateDir }
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$backup = Join-Path $stateDir ("layout-backup-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
& $mod { param($Path) Export-MonitorSwitchBaselineConfig -Path $Path } $backup
Write-Host "Backup written: $backup" -ForegroundColor Green

# --- Build the whole config in memory, then commit once ---------------------
# Applying piecemeal would put displays in overlapping intermediate states.
$cfg = [MonitorSwitchCcd.Config]::Query()

foreach ($t in $target) {
    $cfg.SetRotation($t.Id, [MonitorSwitchCcd.Rotation]$t.Rotation)
    $cfg.SetPosition($t.Id, $t.X, $t.Y)
    "  DId {0} -> {1,-14} {2,-9} at {3},{4}" -f $t.Id, $t.Slot, $t.Rotation, $t.X, $t.Y
}

$cfg.SetPrimary($primaryId)
"  primary -> DId $primaryId"

Write-Host "`nApplying..." -ForegroundColor Yellow
try {
    & $mod { param($Config) Invoke-MonitorSwitchLayout -Config $Config -AllowChanges } $cfg
}
finally {
    Set-MonitorSwitchHdr -Policy off
}

Start-Sleep -Seconds 2
Show-Layout 'AFTER'

# --- Verify against the target ---------------------------------------------
Write-Host "`n=== VERIFY ===" -ForegroundColor Cyan
$live = & $mod { Get-MonitorSwitchDisplayInfo } | Where-Object Active
$bad = 0
foreach ($t in $target) {
    $d = $live | Where-Object DisplayId -eq $t.Id
    if (-not $d) { Write-Host "  DId $($t.Id) MISSING" -ForegroundColor Red; $bad++; continue }
    $pos = "$($d.Position)" -replace '\s+', ','
    $wantPos = "$($t.X),$($t.Y)"
    $rotOk = "$($d.Rotation)" -eq $t.Rotation
    $posOk = $pos -eq $wantPos
    if ($rotOk -and $posOk) {
        Write-Host ("  OK    DId {0} {1}" -f $t.Id, $t.Slot) -ForegroundColor Green
    } else {
        Write-Host ("  WRONG DId {0} {1}: rotation={2} position={3} (wanted {4} / {5})" -f `
            $t.Id, $t.Slot, $d.Rotation, $pos, $t.Rotation, $wantPos) -ForegroundColor Red
        $bad++
    }
}

if ($bad -eq 0) {
    Write-Host "`nAll $($target.Count) connected panels match the physical layout." -ForegroundColor Green
} else {
    Write-Host "`n$bad display(s) did not take. Revert with:" -ForegroundColor Red
    Write-Host "  Import-Module '$modulePath'; Set-MonitorSwitchSetup -Name '$Setup'; Set-MonitorSwitchHdr -Policy off; try { & (Get-Module MonitorSwitch) { Invoke-MonitorSwitchLayout -Config (Import-MonitorSwitchSnapshot -Path '$backup') -AllowChanges } } finally { Set-MonitorSwitchHdr -Policy off }"
}

Write-Host "`nRevert command (keep this):" -ForegroundColor Yellow
Write-Host "  Import-Module '$modulePath'; Set-MonitorSwitchSetup -Name '$Setup'; Set-MonitorSwitchHdr -Policy off; try { & (Get-Module MonitorSwitch) { Invoke-MonitorSwitchLayout -Config (Import-MonitorSwitchSnapshot -Path '$backup') -AllowChanges } } finally { Set-MonitorSwitchHdr -Policy off }"
