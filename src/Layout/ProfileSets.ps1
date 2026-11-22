function Test-MonitorSwitchSetMode {
    param($Config)
    $Config.ContainsKey('mode') -and $Config.mode -eq 'profile-sets'
}

function Test-MonitorSwitchInternalDisplay {
    param($Display)
    [string]$Display.ConnectionType -in @('Internal', 'EmbeddedDisplayPort', 'LVDS', 'EmbeddedUDI')
}

function Get-MonitorSwitchBandMap {
    param($Grid, [string]$Coordinate, [int]$Gap, [string[]]$Ends)
    $bands = @{}
    $band = 0
    $previous = $null
    foreach ($panel in ($Grid | Sort-Object -Property $Coordinate)) {
        $value = $panel.$Coordinate
        if ($null -ne $previous -and $value - $previous -gt $Gap) { $band++ }
        $bands[$panel.DisplayId] = $band
        $previous = $value
    }
    if ($band -gt 2) { throw [FormatException]::new('The laptop layout has more than three bands on an axis; arrange a left/center/right grid before capture.') }
    $labels = @{}
    foreach ($panel in $Grid) {
        $index = $bands[$panel.DisplayId]
        $labels[$panel.DisplayId] = if ($band -eq 0) { 'center' }
        elseif ($index -eq 0) { $Ends[0] }
        elseif ($index -eq $band) { $Ends[1] }
        else { 'center' }
    }
    $labels
}

function ConvertTo-MonitorSwitchSetGrid {
    param($Displays, $Layout)
    $grid = @(foreach ($d in ($Displays | Where-Object Active)) {
        [pscustomobject]@{
            DisplayId = $d.DisplayId; DevicePath = $d.DevicePath; Primary = $d.Primary; Rotation = $d.Rotation
            X = $d.Position.X; Y = $d.Position.Y
            CenterX = $d.Position.X + $d.Width / 2; CenterY = $d.Position.Y + $d.Height / 2
            Column = ''; Row = ''; Slot = ''
            Internal = Test-MonitorSwitchInternalDisplay $d
        }
    })
    $columns = Get-MonitorSwitchBandMap $grid 'CenterX' $Layout.columnGap @('left', 'right')
    $rows = Get-MonitorSwitchBandMap $grid 'CenterY' $Layout.rowGap @('top', 'bottom')
    foreach ($panel in $grid) {
        $panel.Column = $columns[$panel.DisplayId]
        $panel.Row = $rows[$panel.DisplayId]
        $panel.Slot = "$($panel.Row)-$($panel.Column)"
    }
    $grid | Where-Object { -not $_.Internal }
}

function Get-MonitorSwitchSetName {
    param($Displays)
    $models = foreach ($panel in $Displays) {
        if ($panel.DevicePath -match 'DISPLAY#([^#\\]+)') { $Matches[1] } else { 'DISPLAY' }
    }
    $label = (($models | Group-Object | Sort-Object Name | ForEach-Object { "$($_.Name)x$($_.Count)" }) -join '_') -replace '[^a-zA-Z0-9_]', '_'
    $paths = ($Displays.DevicePath | Sort-Object | ForEach-Object { $_.ToLowerInvariant() }) -join "`n"
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $suffix = ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($paths)))).Replace('-', '').Substring(0, 12) }
    finally { $hash.Dispose() }
    "${label}_$suffix"
}

function Read-MonitorSwitchSetRecord {
    param([string]$Path, $Settings)
    $snapshot = Read-MonitorSwitchSavedLayout -Path $Path -Optional -AllowInactive
    if ($null -eq $snapshot) { return }
    $all = @($snapshot.GetDisplays($true))
    $displays = @(ConvertTo-MonitorSwitchSetGrid $all $Settings)
    if (-not $displays) { throw [FormatException]::new("Saved laptop layout '$Path' contains no active external monitors.") }
    [pscustomobject]@{
        Name = Get-MonitorSwitchSetName $displays; Displays = $displays; Path = $Path
        Connections = @($all | Where-Object { -not (Test-MonitorSwitchInternalDisplay $_) } | ForEach-Object { $_.DevicePath })
        CapturedAt = (Get-Item -LiteralPath $Path).LastWriteTimeUtc; Snapshot = $snapshot
    }
}

function Get-MonitorSwitchSetRecord {
    param($Config, [string]$Name)
    $state = Get-MonitorSwitchStateDir
    $paths = @((Join-Path $state 'layout.json'))
    $root = Join-Path $state 'sets'
    if (Test-Path -LiteralPath $root) {
        $paths += @(Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName 'layout.json' })
    }
    $validCount = 0
    $invalid = @()
    foreach ($path in $paths) {
        try { $record = Read-MonitorSwitchSetRecord -Path $path -Settings $Config.layout }
        catch {
            if ($_.Exception.GetBaseException() -isnot [FormatException]) { throw }
            Write-Warning "Ignoring invalid laptop capture '$path': $($_.Exception.Message)"
            $invalid += $_
            continue
        }
        if ($record -and (-not $Name -or $record.Name -eq $Name)) { $validCount++; $record }
    }
    if ($validCount -eq 0 -and $invalid.Count) { throw $invalid[0] }
}

function Save-MonitorSwitchSet {
    param($Config)
    $snapshot = Get-MonitorSwitchDesktopLayout
    $snapshot.ValidateSnapshot($true)
    $active = @($snapshot.GetDisplays($true) | Where-Object { $_.Active -and -not (Test-MonitorSwitchInternalDisplay $_) })
    if (-not $active) { throw 'Enable and arrange the external monitors before capturing a laptop layout.' }
    $null = ConvertTo-MonitorSwitchSetGrid $active $Config.layout
    $name = Get-MonitorSwitchSetName $active
    $state = Get-MonitorSwitchStateDir
    $path = Join-Path $state 'layout.json'
    if ([IO.File]::Exists($path)) {
        $primary = $null
        try { $primary = Read-MonitorSwitchSetRecord -Path $path -Settings $Config.layout }
        catch {
            if ($_.Exception.GetBaseException() -isnot [FormatException]) { throw }
            Write-Warning "Replacing invalid laptop capture '$path': $($_.Exception.Message)"
        }
        if ($primary -and $primary.Name -ne $name) {
            $existing = Get-MonitorSwitchSetRecord -Config $Config -Name $name | Select-Object -First 1
            $path = if ($existing) { $existing.Path } else { Join-Path $state "sets\$name\layout.json" }
        }
    }
    Write-MonitorSwitchSavedLayout -Layout $snapshot -Path $path
    Write-Host "Captured laptop layout '$name' ($($active.Count) external displays) at $path" -ForegroundColor Green
}

function Join-MonitorSwitchSetGrid {
    param($Record, $Live)
    foreach ($saved in $Record.Displays) {
        $match = @($Live | Where-Object DevicePath -eq $saved.DevicePath)
        if ($match.Count -gt 1) { throw 'More than one live display has the same captured connection identity.' }
        if (-not $match) { continue }
        [pscustomobject]@{
            DisplayId = $match[0].DisplayId; DevicePath = $saved.DevicePath
            Primary = $saved.Primary; Rotation = $saved.Rotation
            X = $saved.X; Y = $saved.Y; CenterX = $saved.CenterX; CenterY = $saved.CenterY
            Column = $saved.Column; Row = $saved.Row; Slot = $saved.Slot
        }
    }
}

function Get-MonitorSwitchSetMatch {
    param($Records, $Live)
    foreach ($record in $Records) {
        $grid = @(Join-MonitorSwitchSetGrid -Record $record -Live $Live)
        $unknown = @($Live | Where-Object { $_.DevicePath -notin $record.Connections -and -not (Test-MonitorSwitchInternalDisplay $_) })
        [pscustomobject]@{
            Name = $record.Name; Record = $record; Grid = $grid; CapturedAt = $record.CapturedAt
            Connected = $grid.Count; Count = $record.Displays.Count
            Missing = $record.Displays.Count - $grid.Count
            Matches = $grid.Count -gt 0 -and $unknown.Count -eq 0
        }
    }
}

function Select-MonitorSwitchSetMatch {
    param($Candidates)
    $Candidates | Where-Object Matches | Sort-Object `
        @{ Expression = 'Connected'; Descending = $true }, `
        @{ Expression = 'Missing'; Descending = $false }, `
        @{ Expression = 'CapturedAt'; Descending = $true } | Select-Object -First 1
}

function Select-MonitorSwitchSetPanel {
    param($Grid, $Select)
    if ($Select -eq 'all') { $Grid; return }
    $Grid | Where-Object {
        (-not $Select.ContainsKey('columns') -or $_.Column -in $Select.columns) -and
        (-not $Select.ContainsKey('rows') -or $_.Row -in $Select.rows)
    }
}

function Get-MonitorSwitchSetPlan {
    param($Config, [string]$Name, [string]$Set)
    $live = @(Get-MonitorSwitchDisplayInfo)
    $records = @(Get-MonitorSwitchSetRecord -Config $Config -Name $Set)
    $match = Select-MonitorSwitchSetMatch @(Get-MonitorSwitchSetMatch -Records $records -Live $live)
    if (-not $match) {
        throw "No saved laptop layout matches the connected displays. Arrange the monitors and $(Get-MonitorSwitchCaptureInstruction)."
    }
    $definition = $Config.profiles[$Name]
    if ($definition.select -isnot [string]) {
        foreach ($axis in $definition.select.Keys) {
            $property = if ($axis -eq 'columns') { 'Column' } else { 'Row' }
            foreach ($wanted in $definition.select[$axis]) {
                if ($wanted -notin $match.Record.Displays.$property) {
                    throw "Captured layout '$($match.Name)' has no '$wanted' $axis band. Arrange the full layout with the lid open and $(Get-MonitorSwitchCaptureInstruction)."
                }
            }
        }
    }
    $panels = @(Select-MonitorSwitchSetPanel $match.Grid $definition.select)
    if (-not $panels) { throw "Profile '$Name' matched no connected external monitors in layout '$($match.Name)'." }
    $missing = @(Select-MonitorSwitchSetPanel $match.Record.Displays $definition.select | Where-Object DevicePath -notin $match.Grid.DevicePath)
    if ($missing) { Write-Warning "Requested monitors are disconnected: $($missing.Slot -join ', '). Using connected matches only." }
    $pins = @($live | Where-Object { $_.Active -and (Test-MonitorSwitchInternalDisplay $_) })
    $keep = @($panels.DisplayId) + @($pins | ForEach-Object { $_.DisplayId })
    $disable = @($live | Where-Object DisplayId -notin $keep)
    $compact = $missing.Count -gt 0 -or @($match.Grid | Where-Object DisplayId -notin $panels.DisplayId).Count -gt 0
    $topmost = $definition.ContainsKey('primary') -and $definition.primary -eq 'topmost'
    $primary = if (-not $compact -and -not $topmost) { $panels | Where-Object Primary | Select-Object -First 1 }
    if (-not $primary) {
        $primary = $panels | Sort-Object @{ Expression = 'CenterY'; Descending = -not $topmost }, CenterX | Select-Object -First 1
    }
    $rotations = @{}
    foreach ($panel in $panels) { $rotations[$panel.DisplayId] = $panel.Rotation }
    [pscustomobject]@{
        Match = $match; Live = $live; Panels = $panels; Pins = $pins; Keep = $keep
        Disable = $disable; Compact = $compact; Primary = $primary; Rotations = $rotations
        Positions = @{}; Modes = @{}; Grid = $match.Grid
    }
}
