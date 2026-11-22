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
    foreach ($m in [MonitorSwitch.Windows.DisplayModes]::Query($false)) { $hz[$m.Device] = $m.Current }

    Get-MonitorSwitchDisplayInfo | Sort-Object { $_.Position.Y }, { $_.Position.X } | ForEach-Object {
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

function Compare-MonitorSwitchDisplay {
    <#
    .SYNOPSIS
        Report every readable setting across active displays and flag disagreement.
    .DESCRIPTION
        Reads Windows refresh, resolution, HDR, and SDR white level, plus each
        monitor's brightness, contrast, color preset, and RGB gains.

        Any attribute whose value is not identical on every display is flagged as
        drift. Input source is never compared; it legitimately differs per port.

        A panel with DDC/CI disabled in its own menu reports 'n/a' for the
        monitor-side rows rather than failing the run.
    .EXAMPLE
        Compare-MonitorSwitchDisplay
        if (Compare-MonitorSwitchDisplay | Where-Object Drift) { 'displays disagree' }
    #>
    [CmdletBinding()]
    param([string]$ConfigPath)

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    $ignore = if ($cfg.ContainsKey('comparison') -and $cfg.comparison -and $cfg.comparison.ContainsKey('ignore')) {
        @($cfg.comparison.ignore)
    }
    else { @() }

    $grid = @(Get-MonitorSwitchGrid -Config $cfg)
    $slots = Get-MonitorSwitchSlotMap -Grid $grid
    $modes = [MonitorSwitch.Windows.DisplayModes]::Query($false)
    if (-not $modes) { Write-Warning 'No attached displays found.'; return }

    $hdr = @{}
    $activeIds = @((Get-MonitorSwitchDisplayInfo | Where-Object Active).DisplayId)
    if ($activeIds) {
        foreach ($h in (Get-MonitorSwitchDisplayHdr -DisplayId $activeIds -ErrorAction Stop)) { $hdr[[string]$h.DisplayId] = $h }
    }

    $columns = @()
    $values = @{}   # attribute -> ordered map of column -> value

    function Add-ComparisonValue {
        param([string]$Attribute, [string]$Column, $Value)
        if (-not $values.ContainsKey($Attribute)) { $values[$Attribute] = [ordered]@{} }
        $values[$Attribute][$Column] = $Value
    }

    foreach ($d in ($modes | Sort-Object Y, X)) {
        $slot = $slots[$d.Device]
        $col = if ($slot) { $slot.Slot } else { $d.Device -replace '^\\\\\.\\', '' }
        $columns += $col

        Add-ComparisonValue 'Resolution' $col ('{0}x{1}' -f $d.Width, $d.Height)
        Add-ComparisonValue 'Refresh' $col ('{0}Hz' -f $d.Current)
        Add-ComparisonValue 'BitDepth' $col ('{0}-bit' -f $d.Bpp)

        if ($slot -and $hdr.ContainsKey([string]$slot.DisplayId)) {
            $h = $hdr[[string]$slot.DisplayId]
            Add-ComparisonValue 'HDR' $col $(if ($h.HDREnabled) { 'on' } else { 'off' })
            # Windows represents 80 nits as a raw white level of 1000.
            Add-ComparisonValue 'SdrWhite' $col ('{0} nits' -f [math]::Round($h.SdrWhiteLevel / 1000 * 80))
        }

        $handle = [MonitorSwitch.Windows.MonitorConnection]::Open($d.Device)
        if ($handle -eq [IntPtr]::Zero) {
            foreach ($v in $script:PictureControls) { Add-ComparisonValue $v.Label $col 'n/a' }
            continue
        }
        try {
            foreach ($v in $script:PictureControls) {
                $cur = 0; $max = 0
                $ok = [MonitorSwitch.Windows.MonitorConnection]::TryReadSetting($handle, [byte]$v.Code, [ref]$cur, [ref]$max)
                Add-ComparisonValue $v.Label $col $(if ($ok) { $cur } else { 'n/a' })
            }
        }
        finally { [MonitorSwitch.Windows.MonitorConnection]::Close($handle) }
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

function Show-MonitorSwitchDisplayIdentity {
    <#
    .SYNOPSIS
        Show each display's number and cable type on its physical screen.
    #>
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $infoMap = @{}
    Get-MonitorSwitchDisplayInfo | Where-Object Active | ForEach-Object { $infoMap[$_.GdiDeviceName] = $_ }
    $closeAll = {
        @([System.Windows.Forms.Application]::OpenForms) | ForEach-Object { $_.Close() }
        [System.Windows.Forms.Application]::ExitThread()
    }
    foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
        $info = $infoMap[$screen.DeviceName]
        $text = if ($info) { "$($info.DisplayId)`n$($info.ConnectionType)" } else { "?`nunknown" }
        $form = New-Object System.Windows.Forms.Form
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $form.Bounds = $screen.Bounds
        $form.BackColor = [System.Drawing.Color]::FromArgb(15, 18, 28)
        $form.TopMost = $true
        $form.KeyPreview = $true
        $form.Add_KeyDown({
            if ($args[1].KeyCode -eq [System.Windows.Forms.Keys]::Escape) { & $closeAll }
        }.GetNewClosure())
        $form.Add_Click($closeAll)
        $label = New-Object System.Windows.Forms.Label
        $label.Dock = [System.Windows.Forms.DockStyle]::Fill
        $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $label.ForeColor = [System.Drawing.Color]::White
        $label.Font = New-Object System.Drawing.Font('Segoe UI', 150, [System.Drawing.FontStyle]::Bold)
        $label.Text = $text
        $label.Add_Click($closeAll)
        $form.Controls.Add($label)
        [void]$form.Show()
    }
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 60000
    $timer.Add_Tick($closeAll)
    $timer.Start()
    [System.Windows.Forms.Application]::Run()
}
