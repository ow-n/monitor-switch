function Assert-MonitorSwitchSetTopology {
    param($Config, $Expected)
    if ($Config.DevicePaths.Count -ne $Expected.Count) { throw 'Connected displays changed while preparing the profile. Try again.' }
    foreach ($display in $Expected) {
        if ($Config.DevicePaths[$display.DisplayId - 1] -ne $display.DevicePath) {
            throw 'Display connections changed while preparing the profile. Try again.'
        }
    }
}

function Set-MonitorSwitchSetPosition {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Edits an in-memory CCD config; the public command guards display writes.')]
    param($Config, $Plan)
    $modes = @{}
    foreach ($panel in $Config.GetDisplays($true)) { $modes[$panel.DisplayId] = $panel }
    $left = 0
    if (-not $Plan.Compact) {
        foreach ($panel in $Plan.Panels) {
            $x = $panel.X - $Plan.Primary.X
            $Config.SetPosition($panel.DisplayId, $x, $panel.Y - $Plan.Primary.Y)
            $Plan.Positions[$panel.DisplayId] = @{ X = $x; Y = $panel.Y - $Plan.Primary.Y }
            $left = [math]::Min($left, $x)
        }
    }
    else {
        $columns = @($Plan.Panels | Group-Object Column | Sort-Object { ($_.Group.X | Measure-Object -Minimum).Minimum })
        $positions = @{}
        $x = 0
        foreach ($column in $columns) {
            $y = 0; $width = 0
            foreach ($panel in ($column.Group | Sort-Object Y)) {
                $positions[$panel.DisplayId] = @{ X = $x; Y = $y }
                $y += $modes[$panel.DisplayId].Height
                $width = [math]::Max($width, $modes[$panel.DisplayId].Width)
            }
            $x += $width
        }
        $origin = $positions[$Plan.Primary.DisplayId]
        foreach ($id in $positions.Keys) {
            $p = $positions[$id]
            $Config.SetPosition($id, $p.X - $origin.X, $p.Y - $origin.Y)
            $Plan.Positions[$id] = @{ X = $p.X - $origin.X; Y = $p.Y - $origin.Y }
        }
        $left = -$origin.X
    }
    $pinY = ($Plan.Positions.Values | Where-Object { $_.X -eq $left } | ForEach-Object { $_.Y } | Measure-Object -Minimum).Minimum
    foreach ($pin in $Plan.Pins) {
        $left -= $modes[$pin.DisplayId].Width
        $Config.SetPosition($pin.DisplayId, $left, $pinY)
        $Plan.Positions[$pin.DisplayId] = @{ X = $left; Y = $pinY }
    }
}

function Assert-MonitorSwitchSetMode {
    param($Active, $Modes)
    foreach ($id in $Modes.Keys) {
        $panel = @($Active | Where-Object DisplayId -eq $id)
        $expected = $Modes[$id]
        if ($panel.Count -ne 1 -or $panel[0].Width -ne $expected.Width -or
            $panel[0].Height -ne $expected.Height -or $panel[0].PixelFormat -ne $expected.PixelFormat) {
            throw "Windows changed the requested resolution or pixel format for display $id."
        }
    }
}

function Assert-MonitorSwitchAppliedSet {
    param($Plan)
    $config = Get-MonitorSwitchDesktopLayout
    Assert-MonitorSwitchSetTopology $config $Plan.Live
    $active = @($config.GetDisplays($true) | Where-Object Active)
    if ($active.Count -ne $Plan.Keep.Count -or @($active | Where-Object DisplayId -notin $Plan.Keep).Count) {
        throw 'Windows did not apply the selected display set. Check the connections and display adapter limit.'
    }
    if (@($active | Where-Object { $_.DisplayId -eq $Plan.Primary.DisplayId -and $_.Primary }).Count -ne 1) {
        throw 'Windows did not apply the requested primary display.'
    }
    foreach ($panel in $active) {
        $position = $Plan.Positions[$panel.DisplayId]
        if ($panel.Position.X -ne $position.X -or $panel.Position.Y -ne $position.Y) {
            throw "Windows did not apply the requested position for display $($panel.DisplayId)."
        }
        Assert-MonitorSwitchSetMode -Active $active -Modes $Plan.Modes
        if ($Plan.Rotations.ContainsKey($panel.DisplayId) -and $panel.Rotation -ne $Plan.Rotations[$panel.DisplayId]) {
            throw "Windows did not restore the captured rotation for display $($panel.DisplayId)."
        }
    }
}

function Invoke-MonitorSwitchSetLayout {
    param($Plan)
    $before = Get-MonitorSwitchDesktopLayout
    Assert-MonitorSwitchSetTopology $before $Plan.Live
    $config = $before.Clone()
    $originalModes = @{}
    foreach ($panel in ($before.GetDisplays($true) | Where-Object { $_.Active -and $_.DisplayId -in $Plan.Keep })) {
        $originalModes[$panel.DisplayId] = $panel
    }
    $attempted = $false
    try {
        $config.SelectDisplays([int[]]$Plan.Keep)
        $withModes = @($config.GetDisplays($true) | Where-Object { $_.Active -and $_.Width -gt 0 })
        if ($withModes.Count -ne $Plan.Keep.Count) {
            $attempted = $true
            Invoke-MonitorSwitchDesktopLayout -Layout $config -AllowChanges
            Disable-MonitorSwitchHdr -Confirm:$false
            $config = Get-MonitorSwitchDesktopLayout
            Assert-MonitorSwitchSetTopology $config $Plan.Live
            $active = @($config.GetDisplays($true) | Where-Object Active)
            if ($active.Count -ne $Plan.Keep.Count -or @($active | Where-Object DisplayId -notin $Plan.Keep).Count) {
                throw 'Windows did not enable the selected displays. Check the cables and display adapter limits.'
            }
            Assert-MonitorSwitchSetMode -Active $active -Modes $originalModes
        }
        foreach ($id in $Plan.Rotations.Keys) { $config.SetRotation($id, $Plan.Rotations[$id]) }
        foreach ($panel in ($config.GetDisplays($true) | Where-Object Active)) { $Plan.Modes[$panel.DisplayId] = $panel }
        Set-MonitorSwitchSetPosition -Config $config -Plan $Plan
        $attempted = $true
        Invoke-MonitorSwitchDesktopLayout -Layout $config -AllowChanges
        Disable-MonitorSwitchHdr -Confirm:$false
        Assert-MonitorSwitchAppliedSet -Plan $Plan
    }
    catch {
        if ($attempted) {
            try {
                Disable-MonitorSwitchHdr -Confirm:$false
                try { Invoke-MonitorSwitchDesktopLayout -Layout $before }
                finally { Disable-MonitorSwitchHdr -Confirm:$false }
            }
            catch { Write-Warning "Could not restore the pre-switch layout: $($_.Exception.Message)" }
        }
        throw
    }
}
