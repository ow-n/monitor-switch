#Requires -Version 5.1
Set-StrictMode -Version Latest

# Windows-only: everything here rides on user32 display APIs and the CCD wrapper.
if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
    throw 'MonitorSwitch requires Windows.'
}

#region Native ---------------------------------------------------------------

if (-not ('MonitorSwitch.Display' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace MonitorSwitch {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public ushort dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
    public uint dmFields;
    public int dmPositionX, dmPositionY;
    public uint dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public ushort dmLogPixels;
    public uint dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public uint dmICMMethod, dmICMIntent, dmMediaType, dmDitherType,
                dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct DISPLAY_DEVICE {
    public int cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]  public string DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
    public uint StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
  }

  public class DisplayMode {
    public string Device;
    public string Monitor;
    public uint Width, Height, Bpp, Current;
    public uint[] Available;
  }

  public static class Display {
    const int  ENUM_CURRENT_SETTINGS = -1;
    const uint ATTACHED_TO_DESKTOP   = 0x00000001;
    const uint DM_BITSPERPEL = 0x00040000, DM_PELSWIDTH = 0x00080000,
               DM_PELSHEIGHT = 0x00100000, DM_DISPLAYFREQUENCY = 0x00400000;
    const uint CDS_UPDATEREGISTRY = 0x00000001, CDS_TEST = 0x00000002;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplayDevices(string device, uint devNum, ref DISPLAY_DEVICE info, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplaySettings(string device, int modeNum, ref DEVMODE dm);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int ChangeDisplaySettingsEx(string device, ref DEVMODE dm, IntPtr hwnd, uint flags, IntPtr param);

    static string MonitorName(string adapter) {
      var mon = new DISPLAY_DEVICE();
      mon.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
      if (EnumDisplayDevices(adapter, 0, ref mon, 0) && !string.IsNullOrWhiteSpace(mon.DeviceString))
        return mon.DeviceString;
      return adapter;
    }

    public static List<DisplayMode> Query() {
      var list = new List<DisplayMode>();
      var dev = new DISPLAY_DEVICE();
      dev.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));

      for (uint i = 0; EnumDisplayDevices(null, i, ref dev, 0); i++, dev.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE))) {
        if ((dev.StateFlags & ATTACHED_TO_DESKTOP) == 0) continue;

        var cur = new DEVMODE();
        cur.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
        if (!EnumDisplaySettings(dev.DeviceName, ENUM_CURRENT_SETTINGS, ref cur)) continue;

        // Only rates valid at the resolution and colour depth already in use -
        // this tool never changes resolution.
        var rates = new List<uint>();
        var probe = new DEVMODE();
        probe.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
        for (int m = 0; EnumDisplaySettings(dev.DeviceName, m, ref probe); m++) {
          if (probe.dmPelsWidth  == cur.dmPelsWidth &&
              probe.dmPelsHeight == cur.dmPelsHeight &&
              probe.dmBitsPerPel == cur.dmBitsPerPel &&
              !rates.Contains(probe.dmDisplayFrequency))
            rates.Add(probe.dmDisplayFrequency);
          probe.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
        }
        if (!rates.Contains(cur.dmDisplayFrequency)) rates.Add(cur.dmDisplayFrequency);
        rates.Sort();

        list.Add(new DisplayMode {
          Device  = dev.DeviceName,
          Monitor = MonitorName(dev.DeviceName),
          Width   = cur.dmPelsWidth,
          Height  = cur.dmPelsHeight,
          Bpp     = cur.dmBitsPerPel,
          Current = cur.dmDisplayFrequency,
          Available = rates.ToArray()
        });
      }
      return list;
    }

    public static int SetRefresh(string device, uint hz) {
      var dm = new DEVMODE();
      dm.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
      if (!EnumDisplaySettings(device, ENUM_CURRENT_SETTINGS, ref dm)) return -999;
      dm.dmDisplayFrequency = hz;
      dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_BITSPERPEL | DM_DISPLAYFREQUENCY;
      int test = ChangeDisplaySettingsEx(device, ref dm, IntPtr.Zero, CDS_TEST, IntPtr.Zero);
      if (test != 0) return test;
      return ChangeDisplaySettingsEx(device, ref dm, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
    }
  }
}
'@
}

#endregion

#region Paths and configuration ----------------------------------------------

function Get-MonitorSwitchRoot {
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

function Get-MonitorSwitchDataDir {
    $dir = Join-Path $env:LOCALAPPDATA 'MonitorSwitch'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dir
}

function Get-MonitorSwitchStateDir {
    $dir = Join-Path (Get-MonitorSwitchDataDir) 'state'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dir
}

function Resolve-MonitorSwitchConfigPath {
    # Env override, then the per-machine copy, then the repo template.
    if ($env:MONITOR_SWITCH_CONFIG -and (Test-Path $env:MONITOR_SWITCH_CONFIG)) {
        return (Resolve-Path $env:MONITOR_SWITCH_CONFIG).Path
    }
    $userConfig = Join-Path (Get-MonitorSwitchDataDir) 'monitors.yaml'
    if (Test-Path $userConfig) { return $userConfig }

    $template = Join-Path (Get-MonitorSwitchRoot) 'monitors.yaml'
    if (Test-Path $template) { return $template }

    throw "No monitors.yaml found. Run install.ps1, or set MONITOR_SWITCH_CONFIG."
}

function Get-MonitorSwitchConfig {
    <#
    .SYNOPSIS
        Load and validate monitors.yaml.
    #>
    [CmdletBinding()]
    param([string]$Path)

    if (-not $Path) { $Path = Resolve-MonitorSwitchConfigPath }
    if (-not (Get-Module -ListAvailable powershell-yaml)) {
        throw "powershell-yaml not installed. Run: Install-Module powershell-yaml -Scope CurrentUser"
    }
    Import-Module powershell-yaml -ErrorAction Stop

    $cfg = ConvertFrom-Yaml (Get-Content $Path -Raw)

    foreach ($key in 'layout', 'profiles', 'refresh') {
        if (-not $cfg.ContainsKey($key)) { throw "monitors.yaml is missing the '$key' section." }
    }
    $policy = [string]$cfg.refresh.policy
    if ($policy -notin 'safe', 'max', 'native') {
        throw "refresh.policy must be safe, max or native (got '$policy')."
    }

    $cfg['_path'] = $Path
    $cfg
}

#endregion

#region Geometry -------------------------------------------------------------

function ConvertTo-MonitorGrid {
    <#
    .SYNOPSIS
        Tag each display with a named column and row derived from its position.
    .DESCRIPTION
        DisplayIds are renumbered by Windows whenever a monitor is added or
        removed, so every profile selector keys off geometry instead.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Geometry,
        [Parameter(Mandatory)] [int]$PanelWidth,
        [Parameter(Mandatory)] [int]$PanelHeight
    )

    $colIndex = @{}
    $rowIndex = @{}
    foreach ($d in $Geometry) {
        $colIndex[[string]$d.DisplayId] = [math]::Round($d.X / $PanelWidth)
        $rowIndex[[string]$d.DisplayId] = [math]::Round($d.Y / $PanelHeight)
    }

    $cols = @($colIndex.Values | Sort-Object -Unique)
    $rows = @($rowIndex.Values | Sort-Object -Unique)

    $colNames = Get-AxisName -Count $cols.Count -Axis 'Column'
    $rowNames = Get-AxisName -Count $rows.Count -Axis 'Row'

    foreach ($d in $Geometry) {
        $id = [string]$d.DisplayId
        [pscustomobject]@{
            DisplayId = $d.DisplayId
            X         = $d.X
            Y         = $d.Y
            Column    = $colNames[$cols.IndexOf($colIndex[$id])]
            Row       = $rowNames[$rows.IndexOf($rowIndex[$id])]
        }
    }
}

function Get-AxisName {
    param([int]$Count, [ValidateSet('Column', 'Row')][string]$Axis)

    $ends = if ($Axis -eq 'Column') { @('left', 'right') } else { @('top', 'bottom') }
    switch ($Count) {
        0       { @() }
        1       { , @($ends[0]) }
        2       { $ends }
        3       { @($ends[0], 'middle', $ends[1]) }
        default {
            # 4+ positions: name the ends, number the interior.
            @($ends[0]) + (1..($Count - 2) | ForEach-Object { "mid$_" }) + @($ends[1])
        }
    }
}

function Get-MonitorSwitchBaselineGeometry {
    $file = Join-Path (Get-MonitorSwitchStateDir) 'positions.json'
    if (Test-Path $file) {
        return @(Get-Content $file -Raw | ConvertFrom-Json)
    }
    # No saved baseline: fall back to whatever is live right now.
    @(Get-DisplayInfo | ForEach-Object {
            [pscustomobject]@{ DisplayId = $_.DisplayId; X = $_.Position.X; Y = $_.Position.Y }
        })
}

#endregion

#region Profile resolution ---------------------------------------------------

function Resolve-MonitorSwitchSelection {
    <#
    .SYNOPSIS
        Turn a YAML profile definition into the DisplayIds to keep, primary first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Definition,
        [Parameter(Mandatory)] $Grid
    )

    $select = $Definition.select
    if ($select -is [string] -and $select -eq 'all') { return $null }   # null = full restore

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
        Write-Warning "primary selector matched nothing; falling back to the first kept display."
        return $Keep[0]
    }
    $candidates[0]
}

function Get-MonitorSwitchProfile {
    <#
    .SYNOPSIS
        List configured profiles and what each one would keep active.
    #>
    [CmdletBinding()]
    param([string]$ConfigPath)

    $cfg  = Get-MonitorSwitchConfig -Path $ConfigPath
    $grid = ConvertTo-MonitorGrid -Geometry (Get-MonitorSwitchBaselineGeometry) `
        -PanelWidth $cfg.layout.panelWidth -PanelHeight $cfg.layout.panelHeight

    foreach ($name in ($cfg.profiles.Keys | Sort-Object)) {
        $p    = $cfg.profiles[$name]
        $keep = Resolve-MonitorSwitchSelection -Definition $p -Grid $grid
        [pscustomobject]@{
            Name        = $name
            Description = if ($p.ContainsKey('description')) { $p.description } else { '' }
            Keeps       = if ($null -eq $keep) { 'all (full restore)' } else { $keep -join ', ' }
            Primary     = if ($null -eq $keep) { 'from snapshot' } else { $keep[0] }
        }
    }
}

#endregion

#region Refresh --------------------------------------------------------------

function Resolve-TargetRefresh {
    param([uint32[]]$Available, [uint32]$Current, [string]$Policy, [int]$SafeHz)

    switch ($Policy) {
        'max'    { return ($Available | Measure-Object -Maximum).Maximum }
        'native' { return $null }
        default {
            # A cap only ever lowers. A display already at or below it is left
            # alone - raising it would add back the bandwidth the cap exists to avoid.
            if ($Current -le $SafeHz) { return $Current }
            $under = @($Available | Where-Object { $_ -le $SafeHz })
            if ($under) { ($under | Measure-Object -Maximum).Maximum }
            else { ($Available | Measure-Object -Minimum).Minimum }
        }
    }
}

function Set-MonitorSwitchRefresh {
    <#
    .SYNOPSIS
        Apply the configured refresh-rate policy to every attached display.
    .DESCRIPTION
        Resolution and colour depth are never touched - only refresh rate.
    .EXAMPLE
        Set-MonitorSwitchRefresh -WhatIf
        Set-MonitorSwitchRefresh -Policy max
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [ValidateSet('safe', 'max', 'native')] [string]$Policy,
        [int]$SafeHz,
        [string]$ConfigPath
    )

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    if (-not $Policy) { $Policy = [string]$cfg.refresh.policy }
    if (-not $SafeHz) { $SafeHz = [int]$cfg.refresh.safeHz }

    $overrides = if ($cfg.refresh.ContainsKey('overrides') -and $cfg.refresh.overrides) {
        @($cfg.refresh.overrides)
    }
    else { @() }

    if ($Policy -eq 'native') {
        Write-Host "  refresh policy 'native' - leaving rates untouched." -ForegroundColor DarkGray
        return
    }

    $displays = [MonitorSwitch.Display]::Query()
    if (-not $displays) { Write-Warning 'No attached displays found.'; return }

    Write-Host "`nRefresh policy: $Policy$(if ($Policy -eq 'safe') { " (cap ${SafeHz}Hz)" })" -ForegroundColor Cyan

    foreach ($d in $displays) {
        $cap    = $SafeHz
        $effect = $Policy
        $hit    = $overrides | Where-Object { $d.Monitor -like "*$($_.match)*" } | Select-Object -First 1
        if ($hit) { $cap = [int]$hit.hz; $effect = 'safe' }

        $target = Resolve-TargetRefresh -Available $d.Available -Current $d.Current -Policy $effect -SafeHz $cap
        $label  = '{0,-9} {1,-28} {2}x{3}' -f $d.Device, $d.Monitor, $d.Width, $d.Height

        if ($target -eq $d.Current) {
            Write-Host ("  {0}  {1,3}Hz  already correct" -f $label, $d.Current) -ForegroundColor DarkGray
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($d.Monitor, "set $($d.Current)Hz -> ${target}Hz")) { continue }

        $rc = [MonitorSwitch.Display]::SetRefresh($d.Device, $target)
        if ($rc -eq 0) {
            Write-Host ("  {0}  {1,3}Hz -> {2}Hz" -f $label, $d.Current, $target) -ForegroundColor Green
        }
        else {
            Write-Warning ("{0}: refresh change failed (code {1})" -f $d.Monitor, $rc)
        }
    }
}

#endregion

#region Status, capture, identify --------------------------------------------

function Get-MonitorSwitchStatus {
    <#
    .SYNOPSIS
        Show the live display layout with its derived grid position and refresh rate.
    #>
    [CmdletBinding()]
    param([string]$ConfigPath)

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    # Slots come from the BASELINE, not the live layout: disabling a column would
    # otherwise rename the survivors (a 3-column grid collapsing to left/right).
    $grid = @{}
    ConvertTo-MonitorGrid -Geometry (Get-MonitorSwitchBaselineGeometry) `
        -PanelWidth $cfg.layout.panelWidth -PanelHeight $cfg.layout.panelHeight |
        ForEach-Object { $grid[[string]$_.DisplayId] = $_ }

    $hz = @{}
    foreach ($m in [MonitorSwitch.Display]::Query()) { $hz[$m.Device] = $m.Current }

    Get-DisplayInfo | Sort-Object { $_.Position.Y }, { $_.Position.X } | ForEach-Object {
        $g = $grid[[string]$_.DisplayId]
        # Inactive displays have no GDI device name, so they have no current mode.
        $gdi = $_.GdiDeviceName
        [pscustomobject]@{
            DisplayId  = $_.DisplayId
            State      = if ($_.Active) { 'Active' } else { 'Off' }
            Slot       = if ($g) { "$($g.Row)-$($g.Column)" } else { '-' }
            Name       = $_.DisplayName
            Position   = '{0},{1}' -f $_.Position.X, $_.Position.Y
            Hz         = if ($gdi -and $hz.ContainsKey($gdi)) { $hz[$gdi] } else { $null }
            Rotation   = $_.Rotation
            Connection = $_.ConnectionType
            Primary    = $_.Primary
        }
    }
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
    $xml      = Join-Path $stateDir 'baseline.xml'
    $json     = Join-Path $stateDir 'positions.json'

    if (-not $PSCmdlet.ShouldProcess($stateDir, 'capture baseline layout')) { return }

    Get-DisplayConfig | Export-Clixml $xml
    @(Get-DisplayInfo | ForEach-Object {
            [pscustomobject]@{ DisplayId = $_.DisplayId; X = $_.Position.X; Y = $_.Position.Y }
        }) | ConvertTo-Json | Set-Content $json -Encoding UTF8

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
        $f.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
        $f.Bounds          = $scr.Bounds
        $f.BackColor       = [System.Drawing.Color]::FromArgb(15, 18, 28)
        $f.TopMost         = $true
        $f.KeyPreview      = $true
        # WinForms hands handlers (sender, eventArgs); only the second is needed here.
        $f.Add_KeyDown({
                if ($args[1].KeyCode -eq [System.Windows.Forms.Keys]::Escape) { & $closeAll }
            }.GetNewClosure())
        $f.Add_Click($closeAll)

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Dock      = [System.Windows.Forms.DockStyle]::Fill
        $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $lbl.ForeColor = [System.Drawing.Color]::White
        $lbl.Font      = New-Object System.Drawing.Font('Segoe UI', 150, [System.Drawing.FontStyle]::Bold)
        $lbl.Text      = $text
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

#endregion

#region Switching ------------------------------------------------------------

function Set-MonitorSwitchProfile {
    <#
    .SYNOPSIS
        Apply a named profile, then enforce the refresh policy.
    .EXAMPLE
        Set-MonitorSwitchProfile all
        Set-MonitorSwitchProfile left -SkipRefresh
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [switch]$SkipRefresh,
        [string]$ConfigPath
    )

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    if (-not $cfg.profiles.ContainsKey($Name)) {
        throw "Unknown profile '$Name'. Known: $(($cfg.profiles.Keys | Sort-Object) -join ', ')"
    }

    $baseline = Join-Path (Get-MonitorSwitchStateDir) 'baseline.xml'
    if (-not (Test-Path $baseline)) {
        throw "No baseline snapshot. Arrange your monitors, then run: monitor-switch capture"
    }

    $grid = ConvertTo-MonitorGrid -Geometry (Get-MonitorSwitchBaselineGeometry) `
        -PanelWidth $cfg.layout.panelWidth -PanelHeight $cfg.layout.panelHeight
    $keep = Resolve-MonitorSwitchSelection -Definition $cfg.profiles[$Name] -Grid $grid

    if (-not $PSCmdlet.ShouldProcess($Name, 'apply monitor profile')) { return }

    Write-Host "`nApplying profile: $Name" -ForegroundColor Cyan
    try {
        if ($null -eq $keep) {
            Write-Host '  Restoring every display from the baseline snapshot' -ForegroundColor DarkCyan
            Import-Clixml $baseline | Use-DisplayConfig -UpdateAdapterIds -ErrorAction Stop
        }
        else {
            $all       = @($grid | ForEach-Object { $_.DisplayId })
            $toDisable = @($all | Where-Object { $_ -notin $keep })

            Write-Host ("  Keep:    {0}" -f ($keep -join ', ')) -ForegroundColor Green
            if ($toDisable) {
                Write-Host ("  Disable: {0}" -f ($toDisable -join ', ')) -ForegroundColor DarkYellow
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

    # A restored snapshot carries the refresh rates it was captured with, so the
    # policy has to be re-applied after every switch.
    if (-not $SkipRefresh) {
        Set-MonitorSwitchRefresh -ConfigPath $ConfigPath
    }

    Write-Host "`nDone." -ForegroundColor Green
}

#endregion

#region Shortcuts ------------------------------------------------------------

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
        $file = Join-Path $Directory ("{0}.bat" -f $name.ToUpper())
        $body = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$cli`" switch $name`r`n"
        if ($PSCmdlet.ShouldProcess($file, 'write shortcut')) {
            Set-Content -Path $file -Value $body -Encoding ASCII
            Write-Host "  $file" -ForegroundColor Green
        }
    }
}

#endregion

Export-ModuleMember -Function `
    Get-MonitorSwitchConfig, Get-MonitorSwitchProfile, Get-MonitorSwitchStatus,
Set-MonitorSwitchProfile, Set-MonitorSwitchRefresh, Save-MonitorSwitchBaseline,
Show-MonitorSwitchIdentity, New-MonitorSwitchShortcut
