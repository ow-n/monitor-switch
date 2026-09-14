function Set-MonitorSwitchOsd {
    <#
    .SYNOPSIS
        Write monitor OSD settings over DDC/CI - brightness, contrast, RGB gains.
    .DESCRIPTION
        Talks to each panel's own controller through the video cable, so these
        change the monitor itself, not a Windows or GPU setting. Requires DDC/CI
        enabled in the monitor's own menu.

          apply - write the osd.settings map to every display
          sync  - read osd.reference and copy its values onto the others
          leave - do nothing
    .EXAMPLE
        Set-MonitorSwitchOsd -Policy sync -WhatIf
        Set-MonitorSwitchOsd -Setting Brightness -Value 35
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [ValidateSet('apply', 'sync', 'leave')] [string]$Policy,
        [ValidateSet('Brightness', 'Contrast', 'ColorPreset', 'RedGain', 'GreenGain', 'BlueGain', 'Sharpness', 'PictureMode')]
        [string]$Setting,
        [ValidateRange(0, 255)] [int]$Value,
        [string]$Reference,
        [string]$ProfileName,
        [string]$ConfigPath
    )

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    $sec = Get-MonitorSwitchSection -Config $cfg -Name 'osd' -ProfileName $ProfileName

    # A single -Setting/-Value pair is an ad-hoc write; it bypasses the policy.
    $wanted = @{}
    if ($Setting) {
        $wanted[$Setting] = $Value
        $Policy = 'apply'
    }
    else {
        if (-not $Policy) { $Policy = if ($sec.ContainsKey('policy')) { [string]$sec.policy } else { 'leave' } }
        if ($sec.ContainsKey('settings') -and $sec.settings) {
            foreach ($k in $sec.settings.Keys) { $wanted["$k"] = [int]$sec.settings[$k] }
        }
    }
    if (-not $Reference) { $Reference = if ($sec.ContainsKey('reference')) { [string]$sec.reference } else { 'DISPLAY1' } }

    if ($Policy -eq 'leave') {
        Write-Host "  osd policy 'leave' - leaving panel settings untouched." -ForegroundColor DarkGray
        return
    }
    if ($Policy -eq 'apply' -and -not $wanted.Count) {
        Write-Host '  osd policy is apply but osd.settings is empty - nothing to do.' -ForegroundColor DarkGray
        return
    }

    $slots = Get-MonitorSwitchSlotMap -Config $cfg
    $displays = [MonitorSwitch.Display]::Query()
    if (-not $displays) { Write-Warning 'No attached displays found.'; return }

    if ($Policy -eq 'sync') {
        $refDevice = if ($Reference -like '\\.\*') { $Reference } else { "\\.\$Reference" }
        $ref = $displays | Where-Object Device -eq $refDevice | Select-Object -First 1
        if (-not $ref) {
            throw "Reference display '$Reference' not found. Available: $(($displays.Device) -join ', ')"
        }

        $handle = [MonitorSwitch.Ddc]::Open($ref.X, $ref.Y)
        if ($handle -eq [IntPtr]::Zero) { throw "Could not open $Reference over DDC/CI." }
        try {
            foreach ($v in $script:VcpControls) {
                $cur = 0; $max = 0
                if ([MonitorSwitch.Ddc]::TryGet($handle, [byte]$v.Code, [ref]$cur, [ref]$max)) {
                    $wanted[$v.Label] = $cur
                }
            }
        }
        finally { [MonitorSwitch.Ddc]::Close($handle) }

        $refLabel = if ($slots[$refDevice]) { $slots[$refDevice].Slot } else { $Reference }
        Write-Host "`nOSD sync - reference $refLabel" -ForegroundColor Cyan
        $wanted.GetEnumerator() | Sort-Object Name | ForEach-Object {
            Write-Host ('  {0,-12} {1}' -f $_.Key, $_.Value) -ForegroundColor DarkGray
        }
        $displays = @($displays | Where-Object Device -ne $refDevice)
    }
    else {
        Write-Host "`nOSD apply" -ForegroundColor Cyan
    }

    foreach ($d in $displays) {
        $label = if ($slots[$d.Device]) { $slots[$d.Device].Slot } else { $d.Device }

        $handle = [MonitorSwitch.Ddc]::Open($d.X, $d.Y)
        if ($handle -eq [IntPtr]::Zero) {
            Write-Warning "${label}: DDC/CI unavailable, skipped."
            continue
        }
        try {
            foreach ($name in $wanted.Keys) {
                $ctl = $script:VcpControls | Where-Object Label -eq $name | Select-Object -First 1
                if (-not $ctl) { Write-Warning "Unknown OSD setting '$name', skipped."; continue }

                $target = [int]$wanted[$name]
                $cur = 0; $max = 0
                if (-not [MonitorSwitch.Ddc]::TryGet($handle, [byte]$ctl.Code, [ref]$cur, [ref]$max)) {
                    Write-Warning "${label}: panel did not report $name."
                    continue
                }
                if ($target -gt $max) {
                    Write-Warning "${label}: $target exceeds max $max for $name, skipped."
                    continue
                }
                if ($cur -eq $target) {
                    Write-Host ('  {0,-15} {1,-12} already {2}' -f $label, $name, $target) -ForegroundColor DarkGray
                    continue
                }
                if (-not $PSCmdlet.ShouldProcess("$label $name", "$cur -> $target")) { continue }

                if ([MonitorSwitch.Ddc]::Set($handle, [byte]$ctl.Code, [uint32]$target)) {
                    Write-Host ('  {0,-15} {1,-12} {2} -> {3}' -f $label, $name, $cur, $target) -ForegroundColor Green
                }
                else {
                    Write-Warning "${label} ${name}: write rejected by monitor."
                }
            }
        }
        finally { [MonitorSwitch.Ddc]::Close($handle) }
    }
}
