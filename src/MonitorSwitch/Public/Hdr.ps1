# Windows stores SDR white level raw, where 1000 == 80 nits.
function ConvertTo-MonitorSwitchNitValue { param([int]$Raw) [math]::Round($Raw / 1000 * 80) }
function ConvertTo-MonitorSwitchRawValue { param([int]$Nits) [int][math]::Round($Nits / 80 * 1000) }

function Set-MonitorSwitchHdr {
    <#
    .SYNOPSIS
        Apply the configured HDR policy, SDR content brightness, and Auto HDR.
    .DESCRIPTION
        HDR means 10-bit colour, which is the other big display-bandwidth lever
        next to refresh rate. Windows ships no HDR cmdlet, so this rides on the
        DisplayConfig module.
    .EXAMPLE
        Set-MonitorSwitchHdr -Policy off
        Set-MonitorSwitchHdr -Policy on -SdrNits 300
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [ValidateSet('on', 'off', 'leave')] [string]$Policy,
        [ValidateRange(80, 1000)] [int]$SdrNits,
        [ValidateSet('on', 'off', 'leave')] [string]$AutoHdr,
        [int[]]$DisplayId,
        [string]$ProfileName,
        [string]$ConfigPath
    )

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    $sec = Get-MonitorSwitchSection -Config $cfg -Name 'hdr' -ProfileName $ProfileName

    if (-not $Policy) { $Policy = if ($sec.ContainsKey('policy')) { [string]$sec.policy } else { 'leave' } }
    if (-not $AutoHdr) { $AutoHdr = if ($sec.ContainsKey('autoHdr')) { [string]$sec.autoHdr } else { 'leave' } }
    if (-not $SdrNits -and $sec.ContainsKey('sdrNits')) { $SdrNits = [int]$sec.sdrNits }

    if ($Policy -eq 'leave' -and $AutoHdr -eq 'leave') {
        Write-Host "  hdr policy 'leave' - leaving HDR untouched." -ForegroundColor DarkGray
        return
    }

    $ids = if ($DisplayId) { $DisplayId } else { @((Get-DisplayInfo | Where-Object Active).DisplayId) }
    if (-not $ids) { Write-Warning 'No active displays found.'; return }

    $slots = @{}
    Get-MonitorSwitchGrid -Config $cfg | ForEach-Object { $slots[[string]$_.DisplayId] = $_.Slot }

    Write-Host "`nHDR policy: $Policy (auto-HDR $AutoHdr)" -ForegroundColor Cyan

    foreach ($id in $ids) {
        $label = if ($slots.ContainsKey([string]$id)) { $slots[[string]$id] } else { "display $id" }

        $params = @{ DisplayId = $id }
        if ($Policy -ne 'leave') { $params.EnableHDR = ($Policy -eq 'on') }
        if ($AutoHdr -ne 'leave') { $params.EnableAutoHDR = ($AutoHdr -eq 'on') }
        # SDR white level only means anything while HDR is on.
        if ($SdrNits -and $Policy -ne 'off') { $params.SdrWhiteLevel = ConvertTo-MonitorSwitchRawValue $SdrNits }

        if (-not $PSCmdlet.ShouldProcess($label, "HDR $Policy")) { continue }
        try {
            Set-DisplayHDR @params
            Write-Host ("  {0,-15} HDR {1}" -f $label, $Policy) -ForegroundColor Green
        }
        catch {
            Write-Warning ('{0}: {1}' -f $label, $_.Exception.Message)
        }
    }
}
