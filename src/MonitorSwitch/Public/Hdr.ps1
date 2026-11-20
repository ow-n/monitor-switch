# Windows stores SDR white level raw, where 1000 == 80 nits.
function ConvertTo-MonitorSwitchNitValue { param([int]$Raw) [math]::Round($Raw / 1000 * 80) }
function ConvertTo-MonitorSwitchRawValue { param([int]$Nits) [int][math]::Round($Nits / 80 * 1000) }

function Set-MonitorSwitchHdr {
    <#
    .SYNOPSIS
        Keep Windows HDR, Auto HDR, and HDR video playback disabled.
    .DESCRIPTION
        HDR is locked off. Neither command arguments nor profile overrides can
        enable it. SDR content brightness is left unchanged.
    .EXAMPLE
        Set-MonitorSwitchHdr -Policy off
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [ValidateSet('off')] [string]$Policy = 'off',
        [ValidateRange(80, 1000)] [int]$SdrNits,
        [ValidateSet('off')] [string]$AutoHdr = 'off',
        [int[]]$DisplayId,
        [string]$ProfileName,
        [string]$ConfigPath
    )

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    if ($ProfileName) {
        Write-Verbose "Enforcing HDR off for profile '$ProfileName'."
    }
    if ($PSBoundParameters.ContainsKey('SdrNits')) {
        Write-Warning "SDR content brightness ($SdrNits nits) is not changed while HDR is locked off."
    }

    $ids = @(if ($DisplayId) { $DisplayId | Select-Object -Unique } else { (Get-MonitorSwitchDisplayInfo | Where-Object Active).DisplayId })
    if (-not $ids) { throw 'No active displays found; HDR disablement cannot be verified.' }

    $before = @(Get-MonitorSwitchDisplayHdr -DisplayId $ids -ErrorAction Stop)
    if ($before.Count -ne $ids.Count) { throw 'HDR state was not returned for every requested display.' }

    $slots = @{}
    Get-MonitorSwitchGrid -Config $cfg | ForEach-Object { $slots[[string]$_.DisplayId] = $_.Slot }

    Write-Host "`nHDR locked: $Policy (auto-HDR $AutoHdr)" -ForegroundColor Cyan

    foreach ($display in $before) {
        $id = $display.DisplayId
        $label = if ($slots.ContainsKey([string]$id)) { $slots[[string]$id] } else { "display $id" }

        if ($display.HDREnabled) {
            if (-not $PSCmdlet.ShouldProcess($label, 'disable HDR')) { continue }
            Disable-MonitorSwitchDisplayHdr -DisplayId $id -ErrorAction Stop
        }
    }

    if ($PSCmdlet.ShouldProcess('Windows', 'disable Auto HDR and HDR video playback')) {
        $path = 'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\DirectX\UserGpuPreferences'
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -Force -ErrorAction Stop | Out-Null
        }
        $key = Get-Item -LiteralPath $path -ErrorAction Stop
        try { $oldValue = [string]$key.GetValue('DirectXUserGlobalSettings', '') }
        finally { $key.Dispose() }
        $otherSettings = @($oldValue -split ';' | Where-Object { $_ -and $_ -notmatch '^AutoHDREnable=' })
        $newValue = ((@('AutoHDREnable=0') + $otherSettings) -join ';') + ';'
        New-ItemProperty -LiteralPath $path -Name DirectXUserGlobalSettings -PropertyType String `
            -Value $newValue -Force -ErrorAction Stop | Out-Null
        Disable-MonitorSwitchHdrPlayback
    }

    if (-not $WhatIfPreference) {
        $after = @(Get-MonitorSwitchDisplayHdr -DisplayId $ids -ErrorAction Stop)
        if ($after.Count -ne $ids.Count -or @($after | Where-Object HDREnabled).Count -gt 0) {
            throw 'HDR is not off on every requested display.'
        }
        $global = Get-MonitorSwitchDisplayHdr -Global -ErrorAction Stop
        if ($global.AutoHDREnabled -or $global.HDRPlaybackEnabled) {
            throw 'Auto HDR or HDR video playback is still enabled.'
        }
        foreach ($display in $after) {
            $id = $display.DisplayId
            $label = if ($slots.ContainsKey([string]$id)) { $slots[[string]$id] } else { "display $id" }
            Write-Host ("  {0,-15} HDR off" -f $label) -ForegroundColor Green
        }
    }
}
