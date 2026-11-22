function Resolve-MonitorSwitchRefreshTarget {
    <#
    .SYNOPSIS
        Pick the rate to apply to one display, snapped to a mode it supports.
    #>
    param(
        [uint32[]]$Available,
        [uint32]$Current,
        [string]$Policy,
        [int]$Cap,
        [switch]$Explicit
    )

    switch ($Policy) {
        'native' { return $null }
        'max' { return ($Available | Measure-Object -Maximum).Maximum }
        default {
            # An explicit per-slot target is a request: snap to it in both directions.
            # A policy cap only ever lowers - raising a display back up would add
            # the bandwidth the cap exists to avoid.
            if (-not $Explicit -and $Current -le $Cap) { return $Current }
            $under = @($Available | Where-Object { $_ -le $Cap })
            if ($under) { ($under | Measure-Object -Maximum).Maximum }
            else { ($Available | Measure-Object -Minimum).Minimum }
        }
    }
}

function Set-MonitorSwitchRefreshRate {
    <#
    .SYNOPSIS
        Apply the configured refresh-rate policy to every attached display.
    .DESCRIPTION
        Resolution and colour depth are never touched - only refresh rate.

        Precedence per display:
          1. refresh.displays[<slot>]   explicit target, may raise above safeHz
          2. refresh.overrides[].match  cap matched on monitor name
          3. refresh.policy             safe | max | native
    .EXAMPLE
        Set-MonitorSwitchRefreshRate -WhatIf
        Set-MonitorSwitchRefreshRate -Policy max
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [ValidateSet('safe', 'max', 'native')] [string]$Policy,
        [int]$SafeHz,
        [string]$ProfileName,
        [string]$ConfigPath
    )

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    $sec = Get-MonitorSwitchSection -Config $cfg -Name 'refresh' -ProfileName $ProfileName
    if ($PSBoundParameters.ContainsKey('Policy')) { $sec.policy = $Policy }
    if ($PSBoundParameters.ContainsKey('SafeHz')) { $sec.safeHz = $SafeHz }
    $grid = @(Get-MonitorSwitchGrid -Config $cfg)
    Invoke-MonitorSwitchRefreshPolicy -Settings $sec -Slots (Get-MonitorSwitchSlotMap -Grid $grid) -WhatIf:$WhatIfPreference -Confirm:$false
}

function Invoke-MonitorSwitchRefreshPolicy {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param($Settings, $Slots)

    $Policy = [string]$Settings.policy
    $SafeHz = [int]$Settings.safeHz

    if ($Policy -eq 'native') {
        Write-Host "  refresh policy 'native' - leaving rates untouched." -ForegroundColor DarkGray
        return
    }

    $bySlot = if ($Settings.ContainsKey('displays') -and $Settings.displays) { $Settings.displays } else { @{} }
    $byName = if ($Settings.ContainsKey('overrides') -and $Settings.overrides) { @($Settings.overrides) } else { @() }

    $displays = [MonitorSwitch.Windows.DisplayModes]::Query($true)
    if (-not $displays) { Write-Warning 'No attached displays found.'; return }

    $capNote = if ($Policy -eq 'safe') { " (cap ${SafeHz}Hz)" } else { '' }
    Write-Host "`nRefresh policy: $Policy$capNote" -ForegroundColor Cyan

    foreach ($d in $displays) {
        $slot = $slots[$d.Device]
        $label = if ($slot) { $slot.Slot } else { $d.Device }

        $cap = $SafeHz
        $effective = $Policy
        $explicit = $false

        if ($slot -and $bySlot.ContainsKey($slot.Slot)) {
            $cap = [int]$bySlot[$slot.Slot]
            $effective = 'safe'
            $explicit = $true
            if ($Policy -eq 'safe' -and $cap -gt $SafeHz) {
                Write-Warning "$label pinned to ${cap}Hz, above the ${SafeHz}Hz safe cap."
            }
        }
        else {
            $hit = $byName | Where-Object { $d.Monitor -like "*$($_.match)*" } | Select-Object -First 1
            if ($hit) { $cap = [int]$hit.hz; $effective = 'safe' }
        }

        $target = Resolve-MonitorSwitchRefreshTarget -Available $d.Available -Current $d.Current `
            -Policy $effective -Cap $cap -Explicit:$explicit
        $prefix = '  {0,-15} {1}x{2}' -f $label, $d.Width, $d.Height

        if ($target -eq $d.Current) {
            Write-Host ("{0}  {1,3}Hz  ok" -f $prefix, $d.Current) -ForegroundColor DarkGray
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($label, "set $($d.Current)Hz -> ${target}Hz")) { continue }

        $rc = [MonitorSwitch.Windows.DisplayModes]::SetRefresh($d.Device, $target)
        if ($rc -eq 0) {
            Write-Host ("{0}  {1,3}Hz -> {2}Hz" -f $prefix, $d.Current, $target) -ForegroundColor Green
        }
        else {
            Write-Warning ("{0}: refresh change failed (code {1})" -f $label, $rc)
        }
    }
}
