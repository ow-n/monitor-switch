function Get-MonitorSwitchProfile {
    <#
    .SYNOPSIS
        List configured profiles and what each one would keep active.
    #>
    [CmdletBinding()]
    param([string]$ConfigPath)

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    $grid = Get-MonitorSwitchGrid -Config $cfg

    foreach ($name in ($cfg.profiles.Keys | Sort-Object)) {
        $def = $cfg.profiles[$name]
        $keep = Resolve-MonitorSwitchSelection -Definition $def -Grid $grid
        $refresh = Get-MonitorSwitchSection -Config $cfg -Name 'refresh' -ProfileName $name
        [pscustomobject]@{
            Name        = $name
            Description = if ($def.ContainsKey('description')) { $def.description } else { '' }
            Keeps       = if ($null -eq $keep) { 'all (full restore)' } else { $keep -join ', ' }
            Primary     = if ($null -eq $keep) { 'from snapshot' } else { $keep[0] }
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

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    if (-not $cfg.profiles.ContainsKey($Name)) {
        throw "Unknown profile '$Name'. Known: $(($cfg.profiles.Keys | Sort-Object) -join ', ')"
    }

    $baseline = Join-Path (Get-MonitorSwitchStateDir) 'baseline.xml'
    if (-not (Test-Path $baseline)) {
        throw 'No baseline snapshot. Arrange your monitors, then run: monitor-switch capture'
    }

    $grid = Get-MonitorSwitchGrid -Config $cfg
    $keep = Resolve-MonitorSwitchSelection -Definition $cfg.profiles[$Name] -Grid $grid

    if (-not $PSCmdlet.ShouldProcess($Name, 'apply monitor profile')) { return }

    Write-Host "`nApplying profile: $Name" -ForegroundColor Cyan
    try {
        if ($null -eq $keep) {
            Write-Host '  Restoring every display from the baseline snapshot' -ForegroundColor DarkCyan
            Import-Clixml $baseline | Use-DisplayConfig -UpdateAdapterIds -ErrorAction Stop
        }
        else {
            $all = @($grid | ForEach-Object { $_.DisplayId })
            $toDisable = @($all | Where-Object { $_ -notin $keep })

            Write-Host ('  Keep:    {0}' -f ($keep -join ', ')) -ForegroundColor Green
            if ($toDisable) {
                Write-Host ('  Disable: {0}' -f ($toDisable -join ', ')) -ForegroundColor DarkYellow
            }

            # CCD refuses to disable the primary, so promote a kept display first.
            $config = Import-Clixml $baseline | Set-DisplayPrimary -DisplayId $keep[0] -ErrorAction Stop
            if ($toDisable) {
                $config = $config | Disable-Display -DisplayId $toDisable -ErrorAction Stop
            }
            $config | Use-DisplayConfig -UpdateAdapterIds -ErrorAction Stop
        }
    }
    catch {
        Write-Host "`nERROR applying profile: $_" -ForegroundColor Red
        Write-Host 'If displays look stuck: Settings > System > Display, nudge a monitor, Apply, then retry.' -ForegroundColor Yellow
        throw
    }

    # A restored snapshot carries the settings it was captured with, so every
    # policy has to be re-applied after the switch.
    $common = @{ ProfileName = $Name }
    if ($ConfigPath) { $common.ConfigPath = $ConfigPath }
    if (-not $SkipRefresh) { Set-MonitorSwitchRefresh @common }
    if (-not $SkipHdr) { Set-MonitorSwitchHdr @common }
    if (-not $SkipOsd) { Set-MonitorSwitchOsd @common }

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
    param()

    $stateDir = Get-MonitorSwitchStateDir
    if (-not $PSCmdlet.ShouldProcess($stateDir, 'capture baseline layout')) { return }

    Get-DisplayConfig | Export-Clixml (Join-Path $stateDir 'baseline.xml')
    @(Get-DisplayInfo | ForEach-Object {
            [pscustomobject]@{ DisplayId = $_.DisplayId; X = $_.Position.X; Y = $_.Position.Y }
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
    Get-DisplayInfo | Where-Object Active | ForEach-Object { $infoMap[$_.GdiDeviceName] = $_ }

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

function New-MonitorSwitchShortcut {
    <#
    .SYNOPSIS
        Generate one .bat launcher per profile.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param([string]$Directory, [string]$ConfigPath)

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    if (-not $Directory) {
        $Directory = [Environment]::ExpandEnvironmentVariables([string]$cfg.shortcuts.directory)
    }
    if (-not (Test-Path $Directory)) { New-Item -ItemType Directory -Path $Directory -Force | Out-Null }

    $cli = Join-Path (Get-MonitorSwitchRoot) 'bin\monitor-switch.ps1'

    foreach ($name in ($cfg.profiles.Keys | Sort-Object)) {
        $file = Join-Path $Directory ('{0}.bat' -f $name.ToUpper())
        $body = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$cli`" switch $name`r`n"
        if ($PSCmdlet.ShouldProcess($file, 'write shortcut')) {
            Set-Content -Path $file -Value $body -Encoding ASCII
            Write-Host "  $file" -ForegroundColor Green
        }
    }
}
