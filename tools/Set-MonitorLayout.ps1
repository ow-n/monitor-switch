#Requires -Version 5.1
<#
  Re-map the five panels to their real physical slots after the monitors were
  rearranged. Target grid (top-right slot is empty):

        top-left        top-middle      (none)
        DId 2 / 180     DId 5 / 180

        bottom-left     bottom-middle   bottom-right
        DId 3           DId 4 (primary) DId 1

  Only the top row is mounted inverted, so only DId 2 and DId 5 get Rotate180.
#>

$ErrorActionPreference = 'Stop'
Import-Module DisplayConfig

$W = 3440
$H = 1440

# DisplayId -> slot, rotation, and top-left corner in the virtual desktop.
$target = @(
    [pscustomobject]@{ Id = 2; Slot = 'top-left';      Rotation = 'Rotate180'; X = -$W; Y = -$H }
    [pscustomobject]@{ Id = 5; Slot = 'top-middle';    Rotation = 'Rotate180'; X = 0;   Y = -$H }
    [pscustomobject]@{ Id = 3; Slot = 'bottom-left';   Rotation = 'None';      X = -$W; Y = 0   }
    [pscustomobject]@{ Id = 4; Slot = 'bottom-middle'; Rotation = 'None';      X = 0;   Y = 0   }
    [pscustomobject]@{ Id = 1; Slot = 'bottom-right';  Rotation = 'None';      X = $W;  Y = 0   }
)
$primaryId = 4   # bottom-middle, keeping the previous convention

function Show-Layout {
    param([string]$Title)
    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
    Get-DisplayInfo | Where-Object Active |
        Select-Object DisplayId, Rotation, Position, ConnectionType |
        Sort-Object DisplayId | Format-Table -AutoSize
}

Show-Layout 'BEFORE'

# --- Backup -----------------------------------------------------------------
$stateDir = Join-Path $env:LOCALAPPDATA 'MonitorSwitch\state'
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$backup = Join-Path $stateDir ("layout-backup-{0:yyyyMMdd-HHmmss}.xml" -f (Get-Date))
Get-DisplayConfig | Export-Clixml -Path $backup
Write-Host "Backup written: $backup" -ForegroundColor Green

# --- Build the whole config in memory, then commit once ---------------------
# Applying piecemeal would put displays in overlapping intermediate states.
$cfg = Get-DisplayConfig

foreach ($t in $target) {
    Set-DisplayRotation -DisplayId $t.Id -Rotation $t.Rotation -DisplayConfig $cfg | Out-Null
    Set-DisplayPosition -DisplayId $t.Id -XPosition $t.X -YPosition $t.Y -DisplayConfig $cfg -AllowChanges | Out-Null
    "  DId {0} -> {1,-14} {2,-9} at {3},{4}" -f $t.Id, $t.Slot, $t.Rotation, $t.X, $t.Y
}

Set-DisplayPrimary -DisplayId $primaryId -DisplayConfig $cfg | Out-Null
"  primary -> DId $primaryId"

Write-Host "`nApplying..." -ForegroundColor Yellow
Use-DisplayConfig -DisplayConfig $cfg -AllowChanges -UpdateAdapterIds | Out-Null

Start-Sleep -Seconds 2
Show-Layout 'AFTER'

# --- Verify against the target ---------------------------------------------
Write-Host "`n=== VERIFY ===" -ForegroundColor Cyan
$live = Get-DisplayInfo | Where-Object Active
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
    Write-Host "`nAll five match the physical layout." -ForegroundColor Green
} else {
    Write-Host "`n$bad display(s) did not take. Revert with:" -ForegroundColor Red
    Write-Host "  Import-Module DisplayConfig; Use-DisplayConfig -DisplayConfig (Import-Clixml '$backup') -AllowChanges -UpdateAdapterIds"
}

Write-Host "`nRevert command (keep this):" -ForegroundColor Yellow
Write-Host "  Import-Module DisplayConfig; Use-DisplayConfig -DisplayConfig (Import-Clixml '$backup') -AllowChanges -UpdateAdapterIds"
