# Geometry: turn desktop positions into stable named slots, and resolve a
# profile's selector against them.
#
# DisplayIds are renumbered by Windows whenever a monitor is added or removed,
# so every selector keys off position instead.

function Get-MonitorSwitchAxisName {
    param([int]$Count, [ValidateSet('Column', 'Row')][string]$Axis)

    $ends = if ($Axis -eq 'Column') { @('left', 'right') } else { @('top', 'bottom') }
    switch ($Count) {
        0 { @() }
        1 { , @($ends[0]) }
        2 { $ends }
        3 { @($ends[0], 'middle', $ends[1]) }
        default {
            # 4+ positions: name the ends, number the interior.
            @($ends[0]) + (1..($Count - 2) | ForEach-Object { "mid$_" }) + @($ends[1])
        }
    }
}

function ConvertTo-MonitorSwitchGrid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Geometry,
        [Parameter(Mandatory)] [int]$PanelWidth,
        [Parameter(Mandatory)] [int]$PanelHeight,
        [System.Collections.IDictionary]$ColumnNames,
        [System.Collections.IDictionary]$RowNames
    )

    $colIndex = @{}
    $rowIndex = @{}
    foreach ($d in $Geometry) {
        $colIndex[[string]$d.DisplayId] = [math]::Round($d.X / $PanelWidth)
        $rowIndex[[string]$d.DisplayId] = [math]::Round($d.Y / $PanelHeight)
    }

    $cols = @($colIndex.Values | Sort-Object -Unique)
    $rows = @($rowIndex.Values | Sort-Object -Unique)
    $autoColNames = Get-MonitorSwitchAxisName -Count $cols.Count -Axis 'Column'
    $autoRowNames = Get-MonitorSwitchAxisName -Count $rows.Count -Axis 'Row'

    foreach ($d in $Geometry) {
        $id  = [string]$d.DisplayId
        if ($ColumnNames) {
            $key = [string]$colIndex[$id]
            if (-not $ColumnNames.Contains($key)) { throw "No layout.columnNames entry for column $key." }
            $col = [string]$ColumnNames[$key]
        }
        else { $col = $autoColNames[$cols.IndexOf($colIndex[$id])] }
        if ($RowNames) {
            $key = [string]$rowIndex[$id]
            if (-not $RowNames.Contains($key)) { throw "No layout.rowNames entry for row $key." }
            $row = [string]$RowNames[$key]
        }
        else { $row = $autoRowNames[$rows.IndexOf($rowIndex[$id])] }
        [pscustomobject]@{
            DisplayId = $d.DisplayId
            X         = $d.X
            Y         = $d.Y
            Column    = $col
            Row       = $row
            Slot      = "$row-$col"
        }
    }
}

function Get-MonitorSwitchBaselineGeometry {
    $file = Join-Path (Get-MonitorSwitchStateDir) 'positions.json'
    if (Test-Path $file) {
        return @(Get-Content $file -Raw | ConvertFrom-Json)
    }
    # No saved baseline: fall back to whatever is live right now.
    @(Get-MonitorSwitchDisplayInfo | ForEach-Object {
            [pscustomobject]@{ DisplayId = $_.DisplayId; X = $_.Position.X; Y = $_.Position.Y }
        })
}

function Get-MonitorSwitchGrid {
    param($Config)
    $names = @{}
    if ($Config.layout.ContainsKey('columnNames')) { $names.ColumnNames = $Config.layout.columnNames }
    if ($Config.layout.ContainsKey('rowNames')) { $names.RowNames = $Config.layout.rowNames }
    ConvertTo-MonitorSwitchGrid -Geometry (Get-MonitorSwitchBaselineGeometry) `
        -PanelWidth $Config.layout.panelWidth -PanelHeight $Config.layout.panelHeight @names
}

function Assert-MonitorSwitchTopology {
    $saved = @(Get-MonitorSwitchBaselineGeometry)
    $live = @(Get-MonitorSwitchDisplayInfo)
    if ($saved.Count -ne $live.Count) {
        throw 'Connected monitors changed. Arrange all connected panels and run monitor-switch capture before switching profiles.'
    }
    foreach ($display in $saved) {
        if (-not $display.PSObject.Properties['DevicePath']) {
            throw 'The baseline lacks display identity checks. Arrange all connected panels and run monitor-switch capture.'
        }
        $match = @($live | Where-Object { $_.DevicePath -eq $display.DevicePath })
        if ($match.Count -ne 1 -or $match[0].DisplayId -ne $display.DisplayId) {
            throw 'Display identities or numbering changed. Run monitor-switch capture after arranging all connected panels; the old baseline will not be applied.'
        }
    }
}

function Get-MonitorSwitchSlotMap {
    <#
    .SYNOPSIS
        Map GDI device name (\\.\DISPLAY1) to the display's baseline slot.
    .DESCRIPTION
        The refresh and DDC/CI layers speak GDI device names; everything else
        speaks DisplayId. Get-MonitorSwitchDisplayInfo is the join between them.
    #>
    param($Config)

    $map = @{}
    $bySlot = @{}
    Get-MonitorSwitchGrid -Config $Config | ForEach-Object { $bySlot[[string]$_.DisplayId] = $_ }

    foreach ($info in (Get-MonitorSwitchDisplayInfo | Where-Object Active)) {
        $gdi = $info.GdiDeviceName
        if (-not $gdi) { continue }
        $map[$gdi] = $bySlot[[string]$info.DisplayId]
    }
    $map
}

function Resolve-MonitorSwitchPrimary {
    param($Definition, $Keep)

    $spec = if ($Definition.ContainsKey('primary')) { $Definition.primary } else { 'first' }
    if ($spec -is [string]) {
        if ($spec -eq 'first') { return $Keep[0] }
        # Bare name: treat as a row name if it matches one, else a column name.
        $spec = if ($Keep.Row -contains $spec) { @{ row = $spec } } else { @{ column = $spec } }
    }

    $candidates = @($Keep)
    if ($spec.ContainsKey('column') -and $spec.column) {
        $candidates = @($candidates | Where-Object { $_.Column -eq $spec.column })
    }
    if ($spec.ContainsKey('row') -and $spec.row) {
        $candidates = @($candidates | Where-Object { $_.Row -eq $spec.row })
    }
    if (-not $candidates) {
        Write-Warning 'primary selector matched nothing; falling back to the first kept display.'
        return $Keep[0]
    }
    $candidates[0]
}

function Resolve-MonitorSwitchSelection {
    <#
    .SYNOPSIS
        Turn a profile definition into the DisplayIds to keep, primary first.
        Returns $null for a full restore from the baseline snapshot.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Definition,
        [Parameter(Mandatory)] $Grid
    )

    $select = $Definition.select
    if ($select -is [string] -and $select -eq 'all') { return $null }

    $keep = @($Grid)
    if ($select.ContainsKey('columns') -and $select.columns) {
        $wanted = @($select.columns)
        $keep = @($keep | Where-Object { $_.Column -in $wanted })
    }
    if ($select.ContainsKey('rows') -and $select.rows) {
        $wanted = @($select.rows)
        $keep = @($keep | Where-Object { $_.Row -in $wanted })
    }
    if (-not $keep) {
        throw "Profile selector matched no displays. Check columns/rows against 'monitor-switch status'."
    }

    $primary = Resolve-MonitorSwitchPrimary -Definition $Definition -Keep $keep
    @($primary.DisplayId) + @($keep | Where-Object { $_.DisplayId -ne $primary.DisplayId } |
            ForEach-Object { $_.DisplayId })
}
