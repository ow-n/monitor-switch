# Native Windows desktop layouts, compiled in memory without an external DLL.
if (-not ('MonitorSwitch.Windows.DesktopLayout' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.InteropServices;

namespace MonitorSwitch.Windows {
  [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint LowPart; public int HighPart; }
  [StructLayout(LayoutKind.Sequential)] public struct POINTL { public int x, y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECTL { public int left, top, right, bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct RATIONAL { public uint Numerator, Denominator; }
  [StructLayout(LayoutKind.Sequential)] public struct REGION2D { public uint cx, cy; }

  [StructLayout(LayoutKind.Sequential)]
  public struct PATH_SOURCE_INFO { public LUID adapterId; public uint id, modeInfoIdx, statusFlags; }

  [StructLayout(LayoutKind.Sequential)]
  public struct PATH_TARGET_INFO {
    public LUID adapterId; public uint id, modeInfoIdx, outputTechnology, rotation, scaling;
    public RATIONAL refreshRate; public uint scanLineOrdering; public int targetAvailable; public uint statusFlags;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct PATH_INFO { public PATH_SOURCE_INFO sourceInfo; public PATH_TARGET_INFO targetInfo; public uint flags; }

  [StructLayout(LayoutKind.Sequential)]
  public struct VIDEO_SIGNAL_INFO {
    public ulong pixelRate; public RATIONAL hSyncFreq, vSyncFreq; public REGION2D activeSize, totalSize;
    public uint videoStandard, scanLineOrdering;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct SOURCE_MODE { public uint width, height, pixelFormat; public POINTL position; }

  [StructLayout(LayoutKind.Sequential)]
  public struct DESKTOP_IMAGE_INFO { public POINTL pathSourceSize; public RECTL desktopImageRegion, desktopImageClip; }

  [StructLayout(LayoutKind.Explicit)]
  public struct MODE_INFO {
    [FieldOffset(0)] public uint infoType;
    [FieldOffset(4)] public uint id;
    [FieldOffset(8)] public LUID adapterId;
    [FieldOffset(16)] public VIDEO_SIGNAL_INFO targetMode;
    [FieldOffset(16)] public SOURCE_MODE sourceMode;
    [FieldOffset(16)] public DESKTOP_IMAGE_INFO desktopImageInfo;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct HEADER { public int type; public uint size; public LUID adapterId; public uint id; }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct SOURCE_NAME { public HEADER header; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string viewGdiDeviceName; }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct TARGET_NAME {
    public HEADER header; public uint flags, outputTechnology; public ushort edidManufactureId, edidProductCodeId;
    public uint connectorInstance;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string monitorFriendlyDeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string monitorDevicePath;
  }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct ADAPTER_NAME { public HEADER header; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string adapterDevicePath; }

  [StructLayout(LayoutKind.Sequential)]
  public struct COLOR_INFO { public HEADER header; public uint value; public int colorEncoding; public uint bitsPerColorChannel; }

  [StructLayout(LayoutKind.Sequential)]
  public struct COLOR_INFO_2 { public HEADER header; public uint value; public int colorEncoding; public uint bitsPerColorChannel; public int activeColorMode; }

  [StructLayout(LayoutKind.Sequential)]
  public struct UINT_INFO { public HEADER header; public uint value; }

  public enum ConnectionType : uint {
    Other = 0xFFFFFFFF, HD15 = 0, Svideo = 1, CompositeVideo = 2, ComponentVideo = 3, DVI = 4, HDMI = 5, LVDS = 6,
    D_JPN = 8, SDI = 9, DisplayPort = 10, EmbeddedDisplayPort = 11, UDI = 12, EmbeddedUDI = 13, SDTVDongle = 14,
    Miracast = 15, IndirectWired = 16, IndirectVirtual = 17, USBDisplayPort = 18, Internal = 0x80000000
  }

  public enum Rotation : uint { None = 1, Rotate90 = 2, Rotate180 = 3, Rotate270 = 4 }

  public class DisplayPosition { public int X; public int Y; }

  public class DisplayInfo {
    public int DisplayId; public string DisplayName; public string DevicePath; public ConnectionType ConnectionType;
    public bool Active; public string GdiDeviceName; public DisplayPosition Position; public bool Primary; public Rotation Rotation;
  }

  public class HdrInfo { public int DisplayId; public bool HDREnabled; public uint SdrWhiteLevel; }

  public class DisplayGeometry {
    public int DisplayId; public string DevicePath; public int X; public int Y; public bool Active;
  }

  public static class Native {
    [DllImport("user32.dll")] public static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
    [DllImport("user32.dll")] public static extern int QueryDisplayConfig(uint flags, ref uint paths, [Out] PATH_INFO[] pathArray, ref uint modes, [Out] MODE_INFO[] modeArray, IntPtr topology);
    [DllImport("user32.dll")] public static extern int SetDisplayConfig(uint paths, [In] PATH_INFO[] pathArray, uint modes, [In] MODE_INFO[] modeArray, uint flags);
    [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref SOURCE_NAME info);
    [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref TARGET_NAME info);
    [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref ADAPTER_NAME info);
    [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref COLOR_INFO info);
    [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref COLOR_INFO_2 info);
    [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref UINT_INFO info);
    [DllImport("user32.dll")] public static extern int DisplayConfigSetDeviceInfo(ref UINT_INFO info);

    public static HEADER Header(int type, int size, LUID adapter, uint id) {
      return new HEADER { type = type, size = (uint)size, adapterId = adapter, id = id };
    }

    public static TARGET_NAME TargetName(LUID adapter, uint id) {
      var n = new TARGET_NAME();
      n.header = Header(2, Marshal.SizeOf(typeof(TARGET_NAME)), adapter, id);
      int r = DisplayConfigGetDeviceInfo(ref n);
      if (r != 0) throw new Win32Exception(r);
      return n;
    }

    public static string AdapterPath(LUID adapter) {
      var n = new ADAPTER_NAME();
      n.header = Header(4, Marshal.SizeOf(typeof(ADAPTER_NAME)), adapter, 0);
      int r = DisplayConfigGetDeviceInfo(ref n);
      if (r != 0) throw new Win32Exception(r);
      return n.adapterDevicePath;
    }

    public static string GdiName(LUID adapter, uint sourceId) {
      var n = new SOURCE_NAME();
      n.header = Header(1, Marshal.SizeOf(typeof(SOURCE_NAME)), adapter, sourceId);
      return DisplayConfigGetDeviceInfo(ref n) == 0 ? n.viewGdiDeviceName : null;
    }

    public static bool HdrEnabled(LUID adapter, uint targetId) {
      var c2 = new COLOR_INFO_2();
      c2.header = Header(15, Marshal.SizeOf(typeof(COLOR_INFO_2)), adapter, targetId);
      if (DisplayConfigGetDeviceInfo(ref c2) == 0) return (c2.value & 0x20) != 0 || c2.activeColorMode == 2;
      var c = new COLOR_INFO();
      c.header = Header(9, Marshal.SizeOf(typeof(COLOR_INFO)), adapter, targetId);
      int r = DisplayConfigGetDeviceInfo(ref c);
      if (r != 0) throw new Win32Exception(r);
      return (c.value & 0x2) != 0;
    }

    public static uint SdrWhiteLevel(LUID adapter, uint targetId) {
      var s = new UINT_INFO();
      s.header = Header(11, Marshal.SizeOf(typeof(UINT_INFO)), adapter, targetId);
      return DisplayConfigGetDeviceInfo(ref s) == 0 ? s.value : 0;
    }

    public static void DisableHdr(LUID adapter, uint targetId) {
      var s = new UINT_INFO();
      s.header = Header(16, Marshal.SizeOf(typeof(UINT_INFO)), adapter, targetId);
      s.value = 0;
      if (DisplayConfigSetDeviceInfo(ref s) == 0) return;
      s.header = Header(10, Marshal.SizeOf(typeof(UINT_INFO)), adapter, targetId);
      int r = DisplayConfigSetDeviceInfo(ref s);
      if (r != 0) throw new Win32Exception(r);
    }
  }

  public class DesktopLayout {
    public PATH_INFO[] Paths;
    public MODE_INFO[] Modes;
    public int[] Available;       // Available[DisplayId - 1] = index into Paths
    public string[] DevicePaths;  // parallel to Available
    TARGET_NAME[] targetNames;

    const uint Invalid = 0xFFFFFFFF;
    const uint QueryFlags = 0x11; // QDC_ALL_PATHS | QDC_VIRTUAL_MODE_AWARE

    public static DesktopLayout Query() {
      PATH_INFO[] paths; MODE_INFO[] modes; uint pc, mc; int r;
      do {
        r = Native.GetDisplayConfigBufferSizes(QueryFlags, out pc, out mc);
        if (r != 0) throw new Win32Exception(r);
        paths = new PATH_INFO[pc]; modes = new MODE_INFO[mc];
        r = Native.QueryDisplayConfig(QueryFlags, ref pc, paths, ref mc, modes, IntPtr.Zero);
      } while (r == 122);
      if (r != 0) throw new Win32Exception(r);
      Array.Resize(ref paths, (int)pc); Array.Resize(ref modes, (int)mc);

      var cfg = new DesktopLayout { Paths = paths, Modes = modes };
      var seen = new HashSet<string>();
      var found = new List<Tuple<int, string, int, TARGET_NAME>>();
      for (int i = 0; i < paths.Length; i++) {
        var t = paths[i].targetInfo;
        if (t.targetAvailable == 0) continue;
        string key = t.adapterId.LowPart + ":" + t.adapterId.HighPart + ":" + t.id;
        if (!seen.Add(key)) continue;
        var name = Native.TargetName(t.adapterId, t.id);
        int priority;
        switch (name.outputTechnology) {
          case 0x80000000: priority = 50; break;
          case 11: priority = 100; break;
          case 4: priority = 150; break;
          case 10: priority = 200; break;
          case 5: priority = 250; break;
          default: priority = 300; break;
        }
        found.Add(Tuple.Create(i, Native.AdapterPath(t.adapterId), priority + (int)name.connectorInstance, name));
      }
      var sorted = found.OrderBy(f => f.Item2).ThenBy(f => f.Item3).ToList();
      cfg.Available = sorted.Select(f => f.Item1).ToArray();
      cfg.DevicePaths = sorted.Select(f => f.Item4.monitorDevicePath).ToArray();
      cfg.targetNames = sorted.Select(f => f.Item4).ToArray();
      return cfg;
    }

    static bool Virtual(PATH_INFO p) { return (p.flags & 0x8) != 0; }

    public int SourceIndex(PATH_INFO p) {
      uint v = p.sourceInfo.modeInfoIdx;
      if (v == Invalid) return -1;
      if (!Virtual(p)) return (int)v;
      uint hi = v >> 16; return hi == 0xFFFF ? -1 : (int)hi;
    }

    public int PathIndex(int displayId) {
      if (displayId < 1 || displayId > Available.Length) throw new ArgumentException("Display " + displayId + " was not found.");
      return Available[displayId - 1];
    }

    POINTL? Position(int pathIndex) {
      var p = Paths[pathIndex];
      if ((p.flags & 1) == 0) return null;
      int s = SourceIndex(p);
      if (s < 0 || Modes[s].infoType != 1) return null;
      return Modes[s].sourceMode.position;
    }

    public List<DisplayInfo> GetDisplays() {
      if (targetNames == null) throw new InvalidOperationException("Display names require a live desktop query.");
      var list = new List<DisplayInfo>();
      for (int i = 0; i < Available.Length; i++) {
        var p = Paths[Available[i]];
        var name = targetNames[i];
        bool active = (p.flags & 1) != 0;
        var pos = Position(Available[i]);
        list.Add(new DisplayInfo {
          DisplayId = i + 1,
          DisplayName = name.monitorFriendlyDeviceName,
          DevicePath = name.monitorDevicePath,
          ConnectionType = (ConnectionType)name.outputTechnology,
          Active = active,
          GdiDeviceName = active ? Native.GdiName(p.sourceInfo.adapterId, p.sourceInfo.id) : null,
          Position = pos.HasValue ? new DisplayPosition { X = pos.Value.x, Y = pos.Value.y } : new DisplayPosition(),
          Primary = pos.HasValue && pos.Value.x == 0 && pos.Value.y == 0,
          Rotation = active ? (Rotation)p.targetInfo.rotation : Rotation.None
        });
      }
      return list;
    }

    public List<DisplayGeometry> GetGeometry() {
      var list = new List<DisplayGeometry>();
      for (int i = 0; i < Available.Length; i++) {
        var pos = Position(Available[i]);
        list.Add(new DisplayGeometry {
          DisplayId = i + 1, DevicePath = DevicePaths[i],
          X = pos.HasValue ? pos.Value.x : 0, Y = pos.HasValue ? pos.Value.y : 0,
          Active = (Paths[Available[i]].flags & 1) != 0
        });
      }
      return list;
    }

    public DesktopLayout Clone() {
      return new DesktopLayout {
        Paths = (PATH_INFO[])Paths.Clone(), Modes = (MODE_INFO[])Modes.Clone(),
        Available = (int[])Available.Clone(), DevicePaths = (string[])DevicePaths.Clone()
      };
    }

    public HdrInfo GetHdr(int displayId) {
      var t = Paths[PathIndex(displayId)].targetInfo;
      return new HdrInfo {
        DisplayId = displayId,
        HDREnabled = Native.HdrEnabled(t.adapterId, t.id),
        SdrWhiteLevel = Native.SdrWhiteLevel(t.adapterId, t.id)
      };
    }

    public void DisableHdr(int displayId) {
      var t = Paths[PathIndex(displayId)].targetInfo;
      Native.DisableHdr(t.adapterId, t.id);
    }

    public void SetPrimary(int displayId) {
      var target = Position(PathIndex(displayId));
      if (!target.HasValue) throw new InvalidOperationException("Display " + displayId + " is not active and cannot become primary.");
      var origin = target.Value;
      if (origin.x == 0 && origin.y == 0) return;
      for (int i = 0; i < Modes.Length; i++) {
        if (Modes[i].infoType != 1) continue;
        var pos = Modes[i].sourceMode.position;
        if (pos.x == origin.x && pos.y == origin.y) { pos.x = 0; pos.y = 0; }
        else { pos.x -= origin.x; pos.y -= origin.y; }
        Modes[i].sourceMode.position = pos;
      }
    }

    public void Disable(int displayId) {
      int pi = PathIndex(displayId);
      if ((Paths[pi].flags & 1) == 0) return;
      int oldSource = SourceIndex(Paths[pi]);
      var pos = Position(pi);
      bool cloned = false;
      if (pos.HasValue) {
        for (int j = 0; j < Paths.Length; j++) {
          if (j == pi) continue;
          var other = Position(j);
          if (other.HasValue && other.Value.x == pos.Value.x && other.Value.y == pos.Value.y) { cloned = true; break; }
        }
      }
      if (!cloned && pos.HasValue && pos.Value.x == 0 && pos.Value.y == 0)
        throw new InvalidOperationException("Cannot disable display " + displayId + " because it is the primary display.");
      SOURCE_MODE removed = oldSource >= 0 ? Modes[oldSource].sourceMode : new SOURCE_MODE();

      var newModes = new List<MODE_INFO>();
      var map = new Dictionary<uint, uint>();
      Func<uint, uint> add = old => {
        uint n;
        if (!map.TryGetValue(old, out n)) { n = (uint)newModes.Count; newModes.Add(Modes[old]); map[old] = n; }
        return n;
      };
      Func<uint, uint> remapHigh = v => { uint hi = v >> 16; return hi == 0xFFFF ? v : (add(hi) << 16) | (v & 0xFFFF); };
      Func<uint, uint> remapLow = v => { uint lo = v & 0xFFFF; return lo == 0xFFFF ? v : (v & 0xFFFF0000) | add(lo); };

      for (int j = 0; j < Paths.Length; j++) {
        if (j == pi || (Paths[j].flags & 1) == 0) continue;
        var p = Paths[j];
        if (Virtual(p)) {
          if (p.targetInfo.modeInfoIdx != Invalid) p.targetInfo.modeInfoIdx = remapHigh(p.targetInfo.modeInfoIdx);
          if (p.sourceInfo.modeInfoIdx != Invalid) p.sourceInfo.modeInfoIdx = remapHigh(p.sourceInfo.modeInfoIdx);
          if (p.targetInfo.modeInfoIdx != Invalid) p.targetInfo.modeInfoIdx = remapLow(p.targetInfo.modeInfoIdx);
        } else {
          if (p.targetInfo.modeInfoIdx != Invalid) p.targetInfo.modeInfoIdx = add(p.targetInfo.modeInfoIdx);
          if (p.sourceInfo.modeInfoIdx != Invalid) p.sourceInfo.modeInfoIdx = add(p.sourceInfo.modeInfoIdx);
        }
        Paths[j] = p;
      }
      Paths[pi].sourceInfo.modeInfoIdx = Invalid;
      Paths[pi].targetInfo.modeInfoIdx = Invalid;
      Paths[pi].flags &= ~1u;
      Modes = newModes.ToArray();

      if (!cloned && oldSource >= 0) {
        for (int i = 0; i < Modes.Length; i++) {
          if (Modes[i].infoType != 1) continue;
          var p = Modes[i].sourceMode.position;
          if (removed.position.x > 0 && p.x > removed.position.x) p.x -= (int)removed.width;
          else if (removed.position.x < 0 && p.x < removed.position.x) p.x += (int)removed.width;
          if (removed.position.y > 0 && p.y > removed.position.y) p.y -= (int)removed.height;
          else if (removed.position.y < 0 && p.y < removed.position.y) p.y += (int)removed.height;
          Modes[i].sourceMode.position = p;
        }
      }
    }

    // Saved snapshots carry adapter LUIDs, which change on reboot or driver reload.
    public void UpdateAdapterIds() {
      var live = Query();
      if (live.Available.Length != Available.Length)
        throw new InvalidOperationException("The number of connected displays differs from the saved snapshot.");
      var map = new Dictionary<ulong, LUID>();
      for (int i = 0; i < Available.Length; i++) {
        if (DevicePaths != null && !string.Equals(DevicePaths[i], live.DevicePaths[i], StringComparison.OrdinalIgnoreCase))
          throw new InvalidOperationException("Display " + (i + 1) + " is a different monitor than in the saved snapshot.");
        var oldId = Paths[Available[i]].targetInfo.adapterId;
        var newId = live.Paths[live.Available[i]].targetInfo.adapterId;
        ulong key = Key(oldId);
        LUID existing;
        if (map.TryGetValue(key, out existing)) {
          if (existing.LowPart != newId.LowPart || existing.HighPart != newId.HighPart)
            throw new InvalidOperationException("The display adapter layout has changed since the snapshot was saved.");
        } else map[key] = newId;
      }
      LUID found;
      for (int i = 0; i < Modes.Length; i++)
        if (map.TryGetValue(Key(Modes[i].adapterId), out found)) Modes[i].adapterId = found;
      for (int i = 0; i < Paths.Length; i++) {
        if (map.TryGetValue(Key(Paths[i].sourceInfo.adapterId), out found)) Paths[i].sourceInfo.adapterId = found;
        if (map.TryGetValue(Key(Paths[i].targetInfo.adapterId), out found)) Paths[i].targetInfo.adapterId = found;
      }
    }

    static ulong Key(LUID l) { return ((ulong)(uint)l.HighPart << 32) | l.LowPart; }

    public void Apply() {
      uint flags = 0x20 | 0x80 | 0x200 | 0x8000;
      int r = Native.SetDisplayConfig((uint)Paths.Length, Paths, (uint)Modes.Length, Modes, flags);
      if (r != 0) throw new Win32Exception(r);
    }

    static byte[] ToBytes<T>(T[] items) where T : struct {
      int size = Marshal.SizeOf(typeof(T));
      var bytes = new byte[size * items.Length];
      IntPtr buf = Marshal.AllocHGlobal(size);
      try {
        for (int i = 0; i < items.Length; i++) {
          Marshal.StructureToPtr(items[i], buf, false);
          Marshal.Copy(buf, bytes, i * size, size);
        }
      } finally { Marshal.FreeHGlobal(buf); }
      return bytes;
    }

    static T[] FromBytes<T>(byte[] bytes) where T : struct {
      int size = Marshal.SizeOf(typeof(T));
      if (bytes.Length % size != 0) throw new FormatException("Snapshot data is corrupt.");
      var items = new T[bytes.Length / size];
      IntPtr buf = Marshal.AllocHGlobal(size);
      try {
        for (int i = 0; i < items.Length; i++) {
          Marshal.Copy(bytes, i * size, buf, size);
          items[i] = (T)Marshal.PtrToStructure(buf, typeof(T));
        }
      } finally { Marshal.FreeHGlobal(buf); }
      return items;
    }

    public string PathsBase64() { return Convert.ToBase64String(ToBytes(Paths)); }
    public string ModesBase64() { return Convert.ToBase64String(ToBytes(Modes)); }

    public static DesktopLayout FromSnapshot(string paths, string modes, int[] available, string[] devicePaths) {
      var layout = new DesktopLayout {
        Paths = FromBytes<PATH_INFO>(Convert.FromBase64String(paths)),
        Modes = FromBytes<MODE_INFO>(Convert.FromBase64String(modes)),
        Available = available, DevicePaths = devicePaths
      };
      if (available == null || devicePaths == null || available.Length == 0 || available.Length != devicePaths.Length)
        throw new FormatException("Saved display identities are missing or inconsistent.");
      var indexes = new HashSet<int>();
      var identities = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
      for (int i = 0; i < available.Length; i++) {
        int index = available[i];
        if (index < 0 || index >= layout.Paths.Length || !indexes.Add(index))
          throw new FormatException("Saved display path indexes are invalid.");
        if (String.IsNullOrWhiteSpace(devicePaths[i]) || !identities.Add(devicePaths[i]))
          throw new FormatException("Saved display identities are invalid.");
        var path = layout.Paths[index];
        int source = layout.SourceIndex(path);
        if ((path.flags & 1) == 0 || path.targetInfo.targetAvailable == 0 ||
            source < 0 || source >= layout.Modes.Length || layout.Modes[source].infoType != 1)
          throw new FormatException("The saved layout must contain an active source mode for every display.");
      }
      return layout;
    }
  }
}
'@
}

function Get-MonitorSwitchDesktopLayout {
    [MonitorSwitch.Windows.DesktopLayout]::Query()
}

function Get-MonitorSwitchDisplayInfo {
    (Get-MonitorSwitchDesktopLayout).GetDisplays()
}

function Get-MonitorSwitchDisplayHdr {
    [CmdletBinding()]
    param([int[]]$DisplayId, [switch]$Global)

    if ($Global) {
        $auto = $false
        $path = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\DirectX\UserGpuPreferences'
        if (Test-Path -LiteralPath $path -ErrorAction Stop) {
            $key = Get-Item -LiteralPath $path -ErrorAction Stop
            try {
                $value = [string]$key.GetValue('DirectXUserGlobalSettings', '')
                if ($value -match 'AutoHDREnable=(\d)') { $auto = $Matches[1] -ne '0' }
            }
            finally { $key.Dispose() }
        }
        $playback = $false
        $path = 'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\VideoSettings'
        if (Test-Path -LiteralPath $path -ErrorAction Stop) {
            $key = Get-Item -LiteralPath $path -ErrorAction Stop
            try { $playback = [bool]$key.GetValue('EnableHDRForPlayback', 0) }
            finally { $key.Dispose() }
        }
        return [pscustomobject]@{ AutoHDREnabled = $auto; HDRPlaybackEnabled = $playback }
    }

    $config = Get-MonitorSwitchDesktopLayout
    foreach ($id in $DisplayId) { $config.GetHdr($id) }
}

function Disable-MonitorSwitchDisplayHdr {
    param([Parameter(Mandatory)][int[]]$DisplayId)
    $config = Get-MonitorSwitchDesktopLayout
    foreach ($id in $DisplayId) { $config.DisableHdr($id) }
}

function Disable-MonitorSwitchHdrPlayback {
    $path = 'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\VideoSettings'
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -LiteralPath $path -Name EnableHDRForPlayback -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
}

function Disable-MonitorSwitchAutoHdr {
    $path = 'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\DirectX\UserGpuPreferences'
    if (-not (Test-Path -LiteralPath $path -ErrorAction Stop)) {
        New-Item -Path $path -Force -ErrorAction Stop | Out-Null
    }
    $key = Get-Item -LiteralPath $path -ErrorAction Stop
    try { $oldValue = [string]$key.GetValue('DirectXUserGlobalSettings', '') }
    finally { $key.Dispose() }
    $otherSettings = @($oldValue -split ';' | Where-Object { $_ -and $_ -notmatch '^AutoHDREnable=' })
    $newValue = ((@('AutoHDREnable=0') + $otherSettings) -join ';') + ';'
    New-ItemProperty -LiteralPath $path -Name DirectXUserGlobalSettings -PropertyType String `
        -Value $newValue -Force -ErrorAction Stop | Out-Null
}

function Invoke-MonitorSwitchDesktopLayout {
    param([Parameter(Mandatory)][MonitorSwitch.Windows.DesktopLayout]$Layout)
    $Layout.UpdateAdapterIds()
    $Layout.Apply()
}
