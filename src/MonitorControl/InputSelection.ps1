# Input selection is an enumeration, not a continuous picture setting.
$script:MonitorInputValues = @{ DP1 = 0x0F; DP2 = 0x10; HDMI1 = 0x11; HDMI2 = 0x12 }

function Send-MonitorSwitchInputSelection {
    param([string]$Device, [int]$Target, [bool]$MayWrite)
    $handle = [MonitorSwitch.Windows.MonitorConnection]::Open($Device)
    if ($handle -eq [IntPtr]::Zero) { return $null }
    try {
        $cur = 0; $max = 0
        if (-not [MonitorSwitch.Windows.MonitorConnection]::TryReadSetting($handle, 0x60, [ref]$cur, [ref]$max)) { return $null }
        # Use the same physical handle for the read and write. A later, fresh read verifies the selection.
        [pscustomobject]@{
            Current = $cur
            WriteAccepted = if ($MayWrite -and $cur -ne $Target) { [MonitorSwitch.Windows.MonitorConnection]::WriteSetting($handle, 0x60, [uint32]$Target) }
        }
    }
    finally { [MonitorSwitch.Windows.MonitorConnection]::Close($handle) }
}

function Get-MonitorSwitchInputPlan {
    param($Inputs, $Grid, $Geometry, $Keep)
    foreach ($slot in ($Inputs.Keys | Sort-Object)) {
        $cell = @($Grid | Where-Object Slot -eq $slot)
        if ($cell.Count -ne 1) { throw "Input slot '$slot' does not identify exactly one captured monitor." }
        $panel = $Geometry | Where-Object DisplayId -eq $cell[0].DisplayId
        if ([string]::IsNullOrWhiteSpace($panel.DevicePath)) { throw "Input slot '$slot' has no captured device path." }
        [pscustomobject]@{
            Slot = $slot; DevicePath = $panel.DevicePath; Source = $Inputs[$slot]
            Kept = $null -eq $Keep -or $cell[0].DisplayId -in $Keep
        }
    }
}

function Invoke-MonitorSwitchInputRoute {
    param($Routes)
    $failures = @()
    $attempts = 12
    foreach ($route in $Routes) {
        $target = $script:MonitorInputValues[$route.Source]
        $sent = $false
        $verified = $false
        $reason = 'no DDC/CI input reply'
        for ($attempt = 1; $attempt -le $attempts; $attempt++) {
            if ($attempt -gt 1) { Start-Sleep -Milliseconds 400 }
            # Rebind after a layout change or a panel's hot-plug pulse, not by last-known DISPLAYn.
            $live = @(Get-MonitorSwitchDisplayInfo | Where-Object Active)
            $match = @($live | Where-Object DevicePath -eq $route.DevicePath)
            if ($match.Count -ne 1 -or -not $match[0].GdiDeviceName) { continue }
            $device = $match[0].GdiDeviceName
            if (@($live | Where-Object GdiDeviceName -eq $device).Count -ne 1) {
                $reason = 'ambiguous cloned GDI source'; break
            }
            $reply = Send-MonitorSwitchInputSelection -Device $device -Target $target -MayWrite (-not $sent -and $attempt -lt $attempts)
            if ($null -eq $reply) {
                $reason = if ($sent) { 'write acknowledged, but no read-back' } else { 'no DDC/CI input reply' }
                continue
            }
            if ($reply.Current -eq $target) { $verified = $true; break }
            $reason = 'panel still reports 0x{0:X2}' -f $reply.Current
            if ($null -ne $reply.WriteAccepted) {
                $sent = $reply.WriteAccepted
                if (-not $sent) { $reason += '; write not acknowledged' }
            }
        }
        if ($verified) { Write-Host "  $($route.Slot): $($route.Source) (verified by monitor)" -ForegroundColor Green }
        else { $failures += "$($route.Slot) -> $($route.Source): $reason" }
    }
    if ($failures.Count) { throw "Input selection not verified: $($failures -join '; '). Check DDC/CI and the destination cable/signal." }
}
