function Get-MonitorSwitchProfile {
    <#
    .SYNOPSIS
        List the configured profiles and the screens each would keep.
    #>
    [CmdletBinding()]
    param([string]$ConfigPath)

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    $grid = if (-not ($cfg.ContainsKey('mode') -and $cfg.mode -eq 'alignment')) {
        Get-MonitorSwitchGrid -Config $cfg
    }
    foreach ($name in ($cfg.profiles.Keys | Sort-Object)) {
        $definition = $cfg.profiles[$name]
        $selection = if ($null -ne $grid) { Resolve-MonitorSwitchSelection -Definition $definition -Grid $grid }
        $refresh = Get-MonitorSwitchSection -Config $cfg -Name 'refresh' -ProfileName $name
        [pscustomobject]@{
            Name = $name
            Description = if ($definition.ContainsKey('description')) { $definition.description } else { '' }
            Keeps = if ($null -eq $selection) { 'all' } else { $selection -join ', ' }
            Primary = if ($null -eq $selection) { 'from saved layout' } else { $selection[0] }
            Refresh = '{0}/{1}Hz' -f $refresh.policy, $refresh.safeHz
        }
    }
}

function Disable-MonitorSwitchHdr {
    <#
    .SYNOPSIS
        Disable and verify Windows HDR, Auto HDR, and HDR video playback.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param([int[]]$DisplayId)

    $ids = @(if ($DisplayId) { $DisplayId | Select-Object -Unique } else { (Get-MonitorSwitchDisplayInfo | Where-Object Active).DisplayId })
    if (-not $ids) { throw 'No active displays found; HDR disablement cannot be verified.' }
    $before = @(Get-MonitorSwitchDisplayHdr -DisplayId $ids -ErrorAction Stop)
    if ($before.Count -ne $ids.Count) { throw 'HDR state was not returned for every requested display.' }
    foreach ($id in $ids) {
        if (@($before | Where-Object DisplayId -eq $id).Count -ne 1) {
            throw 'HDR state was not returned for every requested display.'
        }
    }
    if (-not $PSCmdlet.ShouldProcess('Windows and the requested displays', 'disable HDR, Auto HDR, and HDR video playback')) { return }
    foreach ($display in $before) {
        if ($display.HDREnabled) {
            Disable-MonitorSwitchDisplayHdr -DisplayId $display.DisplayId -ErrorAction Stop
        }
    }
    Disable-MonitorSwitchAutoHdr
    Disable-MonitorSwitchHdrPlayback

    $after = @(Get-MonitorSwitchDisplayHdr -DisplayId $ids -ErrorAction Stop)
    if ($after.Count -ne $ids.Count -or @($after | Where-Object HDREnabled).Count) {
        throw 'HDR is not off on every requested display.'
    }
    foreach ($id in $ids) {
        if (@($after | Where-Object DisplayId -eq $id).Count -ne 1) {
            throw 'HDR is not off on every requested display.'
        }
    }
    $global = Get-MonitorSwitchDisplayHdr -Global -ErrorAction Stop
    if ($global.AutoHDREnabled -or $global.HDRPlaybackEnabled) {
        throw 'Auto HDR or HDR video playback is still enabled.'
    }
    Write-Host ('  HDR off on displays {0}; Auto HDR and HDR playback off.' -f ($ids -join ', ')) -ForegroundColor DarkGray
}

function Invoke-MonitorSwitchSafeLayout {
    param($Layout, [array]$OutgoingInputs = @())
    Disable-MonitorSwitchHdr -Confirm:$false
    try {
        Invoke-MonitorSwitchInputRoute -Routes $OutgoingInputs
        Invoke-MonitorSwitchDesktopLayout -Layout $Layout
    }
    finally { Disable-MonitorSwitchHdr -Confirm:$false }
}

function Invoke-MonitorSwitchProfileLayout {
    param($SavedLayout, $TargetLayout, [array]$Release)

    if ($Release.Count) {
        $live = @(Get-MonitorSwitchDisplayInfo)
        $off = @($live | Where-Object { -not $_.Active })
        if (@($off | Where-Object { $_.DevicePath -in $Release.DevicePath }).Count) {
            $stage = $SavedLayout.Clone()
            $primary = @($live | Where-Object { $_.Active -and $_.Primary })
            if ($primary.Count -ne 1) { throw 'Cannot stage the input handoff without a unique active primary.' }
            $stage.SetPrimary($primary[0].DisplayId)
            foreach ($display in $off) {
                if ($display.DevicePath -notin $Release.DevicePath) { $stage.Disable($display.DisplayId) }
            }
            Write-Host '  Temporarily reconnecting outgoing panels for input selection.'
            try {
                Invoke-MonitorSwitchSafeLayout -Layout $stage
                Invoke-MonitorSwitchInputRoute -Routes $Release
            }
            finally {
                # Never leave the desktop in the temporary layout after a rejected handoff.
                Invoke-MonitorSwitchSafeLayout -Layout $TargetLayout
            }
            return
        }
    }
    Invoke-MonitorSwitchSafeLayout -Layout $TargetLayout -OutgoingInputs $Release
}

function Set-MonitorSwitchProfile {
    <#
    .SYNOPSIS
        Apply a saved profile with verified inputs and mandatory HDR-off protection.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [switch]$SkipRefresh,
        [switch]$SkipPicture,
        [string]$ConfigPath
    )
    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    if (-not $cfg.profiles.ContainsKey($Name)) {
        throw "Unknown profile '$Name'. Known: $(($cfg.profiles.Keys | Sort-Object) -join ', ')"
    }
    $saved = Read-MonitorSwitchSavedLayout
    $geometry = @($saved.GetGeometry())
    Assert-MonitorSwitchTopology -Geometry $geometry
    $grid = @(Get-MonitorSwitchGrid -Config $cfg -Geometry $geometry)
    $keep = Resolve-MonitorSwitchSelection -Definition $cfg.profiles[$Name] -Grid $grid
    $target = $saved.Clone()
    if ($null -ne $keep) {
        $target.SetPrimary($keep[0])
        foreach ($id in @($grid.DisplayId | Where-Object { $_ -notin $keep })) { $target.Disable($id) }
    }
    $routes = @(if ($cfg.profiles[$Name].ContainsKey('inputs')) {
        Get-MonitorSwitchInputPlan -Inputs $cfg.profiles[$Name].inputs -Grid $grid -Geometry $geometry -Keep $keep
    })
    if (-not $PSCmdlet.ShouldProcess($Name, 'apply monitor profile')) { return }

    Write-Host "`nApplying profile: $Name" -ForegroundColor Cyan
    try {
        Invoke-MonitorSwitchProfileLayout -SavedLayout $saved -TargetLayout $target -Release @($routes | Where-Object { -not $_.Kept })
    }
    catch {
        Write-Host "`nERROR applying profile: $_" -ForegroundColor Red
        Write-Host 'If displays look stuck: Windows Display Settings, nudge a monitor, Apply, then retry.' -ForegroundColor Yellow
        throw
    }
    $slots = Get-MonitorSwitchSlotMap -Grid $grid
    if (-not $SkipRefresh) {
        Invoke-MonitorSwitchRefreshPolicy -Settings (Get-MonitorSwitchSection -Config $cfg -Name 'refresh' -ProfileName $Name) -Slots $slots
    }
    if (-not $SkipPicture) {
        Invoke-MonitorSwitchPicturePolicy -Settings (Get-MonitorSwitchSection -Config $cfg -Name 'picture' -ProfileName $Name) -Slots $slots
    }
    Invoke-MonitorSwitchInputRoute -Routes @($routes | Where-Object Kept)
    Write-Host "`nDone." -ForegroundColor Green
}
