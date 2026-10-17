function Get-MonitorSwitchStatus {
    <#
    .SYNOPSIS
        Show the live display layout with its baseline slot and refresh rate.
    #>
    [CmdletBinding()]
    param([string]$ConfigPath)

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath

    # Slots come from the BASELINE, not the live layout: disabling a column would
    # otherwise rename the survivors (a 3-column grid collapsing to left/right).
    $grid = @{}
    Get-MonitorSwitchGrid -Config $cfg | ForEach-Object { $grid[[string]$_.DisplayId] = $_ }

    $hz = @{}
    foreach ($m in [MonitorSwitch.Display]::Query()) { $hz[$m.Device] = $m.Current }

    Get-DisplayInfo | Sort-Object { $_.Position.Y }, { $_.Position.X } | ForEach-Object {
        $g = $grid[[string]$_.DisplayId]
        $gdi = $_.GdiDeviceName
        [pscustomobject]@{
            DisplayId  = $_.DisplayId
            State      = if ($_.Active) { 'Active' } else { 'Off' }
            Slot       = if ($g) { $g.Slot } else { '-' }
            Name       = $_.DisplayName
            Position   = '{0},{1}' -f $_.Position.X, $_.Position.Y
            Hz         = if ($gdi -and $hz.ContainsKey($gdi)) { $hz[$gdi] } else { $null }
            Rotation   = $_.Rotation
            Connection = $_.ConnectionType
            Primary    = $_.Primary
        }
    }
}

function Test-MonitorSwitchParity {
    <#
    .SYNOPSIS
        Report every readable setting across active displays and flag disagreement.
    .DESCRIPTION
        Reads both layers:
          GPU side     - refresh, resolution, rotation, HDR, SDR white level
          Monitor side - DDC/CI brightness, contrast, colour preset, RGB gains

        Any attribute whose value is not identical on every display is flagged as
        drift. Input source is never compared; it legitimately differs per port.

        A panel with DDC/CI disabled in its own menu reports 'n/a' for the
        monitor-side rows rather than failing the run.
    .EXAMPLE
        Test-MonitorSwitchParity
        if (Test-MonitorSwitchParity | Where-Object Drift) { 'displays disagree' }
    #>
    [CmdletBinding()]
    param([string]$ConfigPath)

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    $ignore = if ($cfg.ContainsKey('parity') -and $cfg.parity -and $cfg.parity.ContainsKey('ignore')) {
        @($cfg.parity.ignore)
    }
    else { @() }

    $slots = Get-MonitorSwitchSlotMap -Config $cfg
    $modes = [MonitorSwitch.Display]::Query()
    if (-not $modes) { Write-Warning 'No attached displays found.'; return }

    $hdr = @{}
    $activeIds = @((Get-DisplayInfo | Where-Object Active).DisplayId)
    if ($activeIds) {
        try {
            foreach ($h in (Get-DisplayHDR -DisplayId $activeIds)) { $hdr[[string]$h.DisplayId] = $h }
        }
        catch { Write-Verbose "HDR query unavailable: $($_.Exception.Message)" }
    }

    $columns = @()
    $values = @{}   # attribute -> ordered map of column -> value

    function Add-ParityValue {
        param([string]$Attribute, [string]$Column, $Value)
        if (-not $values.ContainsKey($Attribute)) { $values[$Attribute] = [ordered]@{} }
        $values[$Attribute][$Column] = $Value
    }

    foreach ($d in ($modes | Sort-Object Y, X)) {
        $slot = $slots[$d.Device]
        $col = if ($slot) { $slot.Slot } else { $d.Device -replace '^\\\\\.\\', '' }
        $columns += $col

        Add-ParityValue 'Resolution' $col ('{0}x{1}' -f $d.Width, $d.Height)
        Add-ParityValue 'Refresh' $col ('{0}Hz' -f $d.Current)
        Add-ParityValue 'BitDepth' $col ('{0}-bit' -f $d.Bpp)

        if ($slot -and $hdr.ContainsKey([string]$slot.DisplayId)) {
            $h = $hdr[[string]$slot.DisplayId]
            Add-ParityValue 'HDR' $col $(if ($h.HDREnabled) { 'on' } else { 'off' })
            Add-ParityValue 'SdrWhite' $col ('{0} nits' -f (ConvertTo-MonitorSwitchNitValue $h.SdrWhiteLevel))
        }

        $handle = [MonitorSwitch.Ddc]::Open($d.X, $d.Y)
        if ($handle -eq [IntPtr]::Zero) {
            foreach ($v in $script:VcpControls) { Add-ParityValue $v.Label $col 'n/a' }
            continue
        }
        try {
            foreach ($v in $script:VcpControls) {
                $cur = 0; $max = 0
                $ok = [MonitorSwitch.Ddc]::TryGet($handle, [byte]$v.Code, [ref]$cur, [ref]$max)
                Add-ParityValue $v.Label $col $(if ($ok) { $cur } else { 'n/a' })
            }
        }
        finally { [MonitorSwitch.Ddc]::Close($handle) }
    }

    foreach ($attr in $values.Keys) {
        if ($attr -in $ignore) { continue }
        $row = [ordered]@{ Attribute = $attr }
        $seen = @()
        foreach ($col in $columns) {
            $val = if ($values[$attr].Contains($col)) { $values[$attr][$col] } else { '-' }
            $row[$col] = $val
            $seen += [string]$val
        }
        # 'n/a' means the panel could not answer, which is not the same as disagreeing.
        $comparable = @($seen | Where-Object { $_ -ne 'n/a' -and $_ -ne '-' } | Sort-Object -Unique)
        $row['Drift'] = $comparable.Count -gt 1
        [pscustomobject]$row
    }
}
