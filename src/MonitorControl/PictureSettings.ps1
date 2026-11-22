# Input source (0x60) is deliberately excluded from picture sync and comparison.
$script:PictureControls = @(
    [pscustomobject]@{ Code = 0x10; Label = 'Brightness' }
    [pscustomobject]@{ Code = 0x12; Label = 'Contrast' }
    [pscustomobject]@{ Code = 0x14; Label = 'ColorPreset' }
    [pscustomobject]@{ Code = 0x16; Label = 'RedGain' }
    [pscustomobject]@{ Code = 0x18; Label = 'GreenGain' }
    [pscustomobject]@{ Code = 0x1A; Label = 'BlueGain' }
    [pscustomobject]@{ Code = 0x87; Label = 'Sharpness' }
    [pscustomobject]@{ Code = 0xDC; Label = 'PictureMode' }
)

function Set-MonitorSwitchPicture {
    <#
    .SYNOPSIS
        Change the monitor's own brightness, contrast, and other picture settings.
    .DESCRIPTION
        Talks to each panel's own controller through the video cable, so these
        change the monitor itself, not a Windows or GPU setting. Requires DDC/CI
        enabled in the monitor's own menu.

          apply - write the picture.settings map to every display
          sync  - read picture.reference and copy its values onto the others
          leave - do nothing
    .EXAMPLE
        Set-MonitorSwitchPicture -Policy sync -WhatIf
        Set-MonitorSwitchPicture -Setting Brightness -Value 35
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
    $sec = Get-MonitorSwitchSection -Config $cfg -Name 'picture' -ProfileName $ProfileName
    if ($PSBoundParameters.ContainsKey('Policy')) { $sec.policy = $Policy }
    if ($PSBoundParameters.ContainsKey('Reference')) { $sec.reference = $Reference }
    if ($Setting) {
        $sec.settings = @{ $Setting = $Value }
        $sec.policy = 'apply'
    }
    $grid = @(Get-MonitorSwitchGrid -Config $cfg)
    Invoke-MonitorSwitchPicturePolicy -Settings $sec -Slots (Get-MonitorSwitchSlotMap -Grid $grid) -WhatIf:$WhatIfPreference -Confirm:$false
}

function Invoke-MonitorSwitchPicturePolicy {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param($Settings, $Slots)

    $Policy = if ($Settings.ContainsKey('policy')) { [string]$Settings.policy } else { 'leave' }
    $Reference = if ($Settings.ContainsKey('reference')) { [string]$Settings.reference } else { 'DISPLAY1' }
    $wanted = @{}
    if ($Settings.ContainsKey('settings') -and $Settings.settings) {
        foreach ($key in $Settings.settings.Keys) { $wanted[$key] = [int]$Settings.settings[$key] }
    }

    if ($Policy -eq 'leave') {
        Write-Host "  picture policy 'leave' - leaving picture settings untouched." -ForegroundColor DarkGray
        return
    }
    if ($Policy -eq 'apply' -and -not $wanted.Count) {
        Write-Host '  picture policy is apply but picture.settings is empty - nothing to do.' -ForegroundColor DarkGray
        return
    }

    $displays = @(Get-MonitorSwitchDisplayInfo | Where-Object Active)
    if (-not $displays) { Write-Warning 'No attached displays found.'; return }

    if ($Policy -eq 'sync') {
        $refDevice = if ($Reference -like '\\.\*') { $Reference } else { "\\.\$Reference" }
        $ref = $displays | Where-Object GdiDeviceName -eq $refDevice | Select-Object -First 1
        if (-not $ref) {
            throw "Reference display '$Reference' not found. Available: $(($displays.GdiDeviceName) -join ', ')"
        }

        $handle = [MonitorSwitch.Windows.MonitorConnection]::Open($ref.GdiDeviceName)
        if ($handle -eq [IntPtr]::Zero) { throw "Could not open $Reference over DDC/CI." }
        try {
            foreach ($v in $script:PictureControls) {
                $cur = 0; $max = 0
                if ([MonitorSwitch.Windows.MonitorConnection]::TryReadSetting($handle, [byte]$v.Code, [ref]$cur, [ref]$max)) {
                    $wanted[$v.Label] = $cur
                }
            }
        }
        finally { [MonitorSwitch.Windows.MonitorConnection]::Close($handle) }

        $refLabel = if ($slots[$refDevice]) { $slots[$refDevice].Slot } else { $Reference }
        Write-Host "`nPicture sync - reference $refLabel" -ForegroundColor Cyan
        $wanted.GetEnumerator() | Sort-Object Name | ForEach-Object {
            Write-Host ('  {0,-12} {1}' -f $_.Key, $_.Value) -ForegroundColor DarkGray
        }
        $displays = @($displays | Where-Object GdiDeviceName -ne $refDevice)
    }
    else {
        Write-Host "`nPicture apply" -ForegroundColor Cyan
    }

    foreach ($d in $displays) {
        $label = if ($slots[$d.GdiDeviceName]) { $slots[$d.GdiDeviceName].Slot } else { $d.GdiDeviceName }

        $handle = [MonitorSwitch.Windows.MonitorConnection]::Open($d.GdiDeviceName)
        if ($handle -eq [IntPtr]::Zero) {
            Write-Warning "${label}: DDC/CI unavailable, skipped."
            continue
        }
        try {
            foreach ($name in $wanted.Keys) {
                $ctl = $script:PictureControls | Where-Object Label -eq $name | Select-Object -First 1
                if (-not $ctl) { Write-Warning "Unknown picture setting '$name', skipped."; continue }

                $target = [int]$wanted[$name]
                $cur = 0; $max = 0
                if (-not [MonitorSwitch.Windows.MonitorConnection]::TryReadSetting($handle, [byte]$ctl.Code, [ref]$cur, [ref]$max)) {
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

                if ([MonitorSwitch.Windows.MonitorConnection]::WriteSetting($handle, [byte]$ctl.Code, [uint32]$target)) {
                    Write-Host ('  {0,-15} {1,-12} {2} -> {3}' -f $label, $name, $cur, $target) -ForegroundColor Green
                }
                else {
                    Write-Warning "${label} ${name}: write rejected by monitor."
                }
            }
        }
        finally { [MonitorSwitch.Windows.MonitorConnection]::Close($handle) }
    }
}
