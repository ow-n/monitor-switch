function Get-MonitorSwitchProfile {
    <#
    .SYNOPSIS
        List configured profiles and what each one would keep active.
    #>
    [CmdletBinding()]
    param([string]$ConfigPath)

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    $grid = if (-not ($cfg.ContainsKey('mode') -and $cfg.mode -eq 'alignment')) {
        Get-MonitorSwitchGrid -Config $cfg
    }

    foreach ($name in ($cfg.profiles.Keys | Sort-Object)) {
        $def = $cfg.profiles[$name]
        $selection = if ($null -ne $grid) { Resolve-MonitorSwitchSelection -Definition $def -Grid $grid }
        $refresh = Get-MonitorSwitchSection -Config $cfg -Name 'refresh' -ProfileName $name
        [pscustomobject]@{
            Name        = $name
            Description = if ($def.ContainsKey('description')) { $def.description } else { '' }
            Keeps       = if ($null -eq $selection) { 'all (full restore)' } else { $selection -join ', ' }
            Primary     = if ($null -eq $selection) { 'from snapshot' } else { $selection[0] }
            Refresh     = '{0}/{1}Hz' -f $refresh.policy, $refresh.safeHz
        }
    }
}

function Set-MonitorSwitchProfile {
    <#
    .SYNOPSIS
        Apply a named profile, then enforce the refresh, HDR, and OSD policies.
    .EXAMPLE
        Set-MonitorSwitchProfile all
        Set-MonitorSwitchProfile left -SkipRefresh
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [switch]$SkipRefresh,
        [switch]$SkipHdr,
        [switch]$SkipOsd,
        [string]$ConfigPath
    )

    if ($SkipHdr) { throw 'HDR is locked off; -SkipHdr cannot bypass the SDR policy.' }

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    if (-not $cfg.profiles.ContainsKey($Name)) {
        throw "Unknown profile '$Name'. Known: $(($cfg.profiles.Keys | Sort-Object) -join ', ')"
    }

    if (-not (Test-MonitorSwitchBaseline)) {
        throw "No baseline snapshot. Connect and arrange all monitors, then run setups\$script:MonitorSwitchSetup\CAPTURE.bat on this machine."
    }

    Assert-MonitorSwitchTopology
    $grid = @()
    $keep = $null
    if ($cfg.profiles[$Name].select -isnot [string] -or $cfg.profiles[$Name].select -ne 'all') {
        $grid = Get-MonitorSwitchGrid -Config $cfg
        $keep = Resolve-MonitorSwitchSelection -Definition $cfg.profiles[$Name] -Grid $grid
    }

    $routes = @(if (-not $SkipOsd -and $cfg.profiles[$Name].ContainsKey('inputs')) {
        if (-not $grid) { $grid = Get-MonitorSwitchGrid -Config $cfg }
        Get-MonitorSwitchInputPlan -Inputs $cfg.profiles[$Name].inputs -Grid $grid -Keep $keep
    })
    if (-not $PSCmdlet.ShouldProcess($Name, 'apply monitor profile')) { return }

    Write-Host "`nApplying profile: $Name" -ForegroundColor Cyan
    try {
        Set-MonitorSwitchHdr -Policy off -ConfigPath $cfg['_path']
        $config = Import-MonitorSwitchBaselineConfig
        if ($null -eq $keep) {
            Write-Host '  Restoring every display from the baseline snapshot' -ForegroundColor DarkCyan
        }
        else {
            $all = @($grid | ForEach-Object { $_.DisplayId })
            $toDisable = @($all | Where-Object { $_ -notin $keep })

            Write-Host ('  Keep:    {0}' -f ($keep -join ', ')) -ForegroundColor Green
            if ($toDisable) {
                Write-Host ('  Disable: {0}' -f ($toDisable -join ', ')) -ForegroundColor DarkYellow
            }

            # CCD refuses to disable the primary, so promote a kept display first.
            if ($config) {
                $config.SetPrimary($keep[0])
                foreach ($id in $toDisable) { $config.Disable($id) }
            }
        }
        $release = @($routes | Where-Object { -not $_.Kept })
        Invoke-MonitorSwitchHandoffLayout -Config $config -Release $release -ConfigPath $cfg['_path']
    }
    catch {
        Write-Host "`nERROR applying profile: $_" -ForegroundColor Red
        Write-Host 'If displays look stuck: Settings > System > Display, nudge a monitor, Apply, then retry.' -ForegroundColor Yellow
        throw
    }
    finally {
        Set-MonitorSwitchHdr -Policy off -ProfileName $Name -ConfigPath $cfg['_path']
    }

    # A restored snapshot carries the settings it was captured with, so every
    # policy has to be re-applied after the switch.
    $common = @{ ProfileName = $Name }
    if ($ConfigPath) { $common.ConfigPath = $ConfigPath }
    if (-not $SkipRefresh) { Set-MonitorSwitchRefresh @common }
    if (-not $SkipOsd) { Set-MonitorSwitchOsd @common }
    Invoke-MonitorSwitchInputRoute -Routes @($routes | Where-Object Kept)

    Write-Host "`nDone." -ForegroundColor Green
}

function Save-MonitorSwitchBaseline {
    <#
    .SYNOPSIS
        Snapshot the current layout as the baseline every profile is derived from.
    .DESCRIPTION
        Re-run this after physically rearranging monitors, changing rotation, or
        adding/removing a display - DisplayIds renumber and the old snapshot goes stale.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([string]$ConfigPath)

    $stateDir = Get-MonitorSwitchStateDir
    if (-not $PSCmdlet.ShouldProcess($stateDir, 'capture baseline layout')) { return }

    $displays = @(Get-MonitorSwitchDisplayInfo)
    if (@($displays | Where-Object { -not $_.Active }).Count -gt 0) {
        throw 'Enable every connected display before capture. A handoff or single-screen layout must not replace the full baseline.'
    }
    Set-MonitorSwitchHdr -Policy off -ConfigPath $ConfigPath
    [void][System.IO.Directory]::CreateDirectory($stateDir)
    Export-MonitorSwitchBaselineConfig -Path (Join-Path $stateDir 'baseline.json')
    @($displays | ForEach-Object {
            [pscustomobject]@{ DisplayId = $_.DisplayId; DevicePath = $_.DevicePath; X = $_.Position.X; Y = $_.Position.Y }
        }) | ConvertTo-Json | Set-Content (Join-Path $stateDir 'positions.json') -Encoding UTF8

    Write-Host "Baseline saved to $stateDir" -ForegroundColor Green
}

function Show-MonitorSwitchIdentity {
    <#
    .SYNOPSIS
        Flash each display's DisplayId and connection type on the physical panel.
    .DESCRIPTION
        Identical panels are impossible to tell apart in Settings. Click any
        screen or press Esc to dismiss; auto-closes after 60 seconds.
    #>
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $infoMap = @{}
    Get-MonitorSwitchDisplayInfo | Where-Object Active | ForEach-Object { $infoMap[$_.GdiDeviceName] = $_ }

    # Close handlers use only static calls so they survive scriptblock scoping.
    $closeAll = {
        @([System.Windows.Forms.Application]::OpenForms) | ForEach-Object { $_.Close() }
        [System.Windows.Forms.Application]::ExitThread()
    }

    foreach ($scr in [System.Windows.Forms.Screen]::AllScreens) {
        $info = $infoMap[$scr.DeviceName]
        $text = if ($info) { "$($info.DisplayId)`n$($info.ConnectionType)" } else { "?`nunknown" }

        $f = New-Object System.Windows.Forms.Form
        $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $f.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $f.Bounds = $scr.Bounds
        $f.BackColor = [System.Drawing.Color]::FromArgb(15, 18, 28)
        $f.TopMost = $true
        $f.KeyPreview = $true
        # WinForms hands handlers (sender, eventArgs); only the second is needed here.
        $f.Add_KeyDown({
                if ($args[1].KeyCode -eq [System.Windows.Forms.Keys]::Escape) { & $closeAll }
            }.GetNewClosure())
        $f.Add_Click($closeAll)

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Dock = [System.Windows.Forms.DockStyle]::Fill
        $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $lbl.ForeColor = [System.Drawing.Color]::White
        $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 150, [System.Drawing.FontStyle]::Bold)
        $lbl.Text = $text
        $lbl.Add_Click($closeAll)
        $f.Controls.Add($lbl)
        [void]$f.Show()
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 60000
    $timer.Add_Tick($closeAll)
    $timer.Start()
    [System.Windows.Forms.Application]::Run()
}
