# Windows CCD (Connecting and Configuring Displays) layer, compiled inline so the
# module has no third-party binary dependency. DisplayId numbering matches the
# DisplayConfig module it replaces, so existing positions.json files stay valid.

if (-not ('MonitorSwitchCcd.Config' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.InteropServices;

namespace MonitorSwitchCcd {
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

  public class Config {
    public PATH_INFO[] Paths;
    public MODE_INFO[] Modes;
    public int[] Available;       // Available[DisplayId - 1] = index into Paths
    public string[] DevicePaths;  // parallel to Available

    const uint Invalid = 0xFFFFFFFF;
    const uint QueryFlags = 0x11; // QDC_ALL_PATHS | QDC_VIRTUAL_MODE_AWARE

    public static Config Query() {
      PATH_INFO[] paths; MODE_INFO[] modes; uint pc, mc; int r;
      do {
        r = Native.GetDisplayConfigBufferSizes(QueryFlags, out pc, out mc);
        if (r != 0) throw new Win32Exception(r);
        paths = new PATH_INFO[pc]; modes = new MODE_INFO[mc];
        r = Native.QueryDisplayConfig(QueryFlags, ref pc, paths, ref mc, modes, IntPtr.Zero);
      } while (r == 122);
      if (r != 0) throw new Win32Exception(r);
      Array.Resize(ref paths, (int)pc); Array.Resize(ref modes, (int)mc);

      var cfg = new Config { Paths = paths, Modes = modes };
      var seen = new HashSet<string>();
      var found = new List<Tuple<int, string, int, string>>();
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
        found.Add(Tuple.Create(i, Native.AdapterPath(t.adapterId), priority + (int)name.connectorInstance, name.monitorDevicePath));
      }
      var sorted = found.OrderBy(f => f.Item2).ThenBy(f => f.Item3).ToList();
      cfg.Available = sorted.Select(f => f.Item1).ToArray();
      cfg.DevicePaths = sorted.Select(f => f.Item4).ToArray();
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

    public bool IsPrimary(int displayId) {
      var pos = Position(PathIndex(displayId));
      return pos.HasValue && pos.Value.x == 0 && pos.Value.y == 0;
    }

    public List<DisplayInfo> GetDisplays() {
      var list = new List<DisplayInfo>();
      for (int i = 0; i < Available.Length; i++) {
        var p = Paths[Available[i]];
        var name = Native.TargetName(p.targetInfo.adapterId, p.targetInfo.id);
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

    public void SetRotation(int displayId, Rotation rotation) {
      Paths[PathIndex(displayId)].targetInfo.rotation = (uint)rotation;
    }

    public void SetPosition(int displayId, int x, int y) {
      int s = SourceIndex(Paths[PathIndex(displayId)]);
      if (s < 0) throw new InvalidOperationException("Display " + displayId + " is not active.");
      Modes[s].sourceMode.position = new POINTL { x = x, y = y };
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

    public void Apply(bool allowChanges) {
      uint flags = 0x20 | 0x80 | 0x200 | 0x8000;
      if (allowChanges) flags |= 0x400;
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

    public static Config FromSnapshot(string paths, string modes, int[] available, string[] devicePaths) {
      return new Config {
        Paths = FromBytes<PATH_INFO>(Convert.FromBase64String(paths)),
        Modes = FromBytes<MODE_INFO>(Convert.FromBase64String(modes)),
        Available = available, DevicePaths = devicePaths
      };
    }

    public static PATH_INFO MakePath(uint srcLow, int srcHigh, uint srcId, uint srcIdx, uint srcStatus,
        uint tgtLow, int tgtHigh, uint tgtId, uint tgtIdx, uint tech, uint rotation, uint scaling,
        uint refNum, uint refDen, uint scan, bool available, uint tgtStatus, uint flags) {
      var p = new PATH_INFO();
      p.sourceInfo = new PATH_SOURCE_INFO { adapterId = new LUID { LowPart = srcLow, HighPart = srcHigh }, id = srcId, modeInfoIdx = srcIdx, statusFlags = srcStatus };
      p.targetInfo = new PATH_TARGET_INFO {
        adapterId = new LUID { LowPart = tgtLow, HighPart = tgtHigh }, id = tgtId, modeInfoIdx = tgtIdx,
        outputTechnology = tech, rotation = rotation, scaling = scaling,
        refreshRate = new RATIONAL { Numerator = refNum, Denominator = refDen },
        scanLineOrdering = scan, targetAvailable = available ? 1 : 0, statusFlags = tgtStatus
      };
      p.flags = flags;
      return p;
    }

    static MODE_INFO Mode(uint type, uint id, uint low, int high) {
      return new MODE_INFO { infoType = type, id = id, adapterId = new LUID { LowPart = low, HighPart = high } };
    }

    public static MODE_INFO MakeTargetMode(uint id, uint low, int high, ulong pixelRate, uint hNum, uint hDen,
        uint vNum, uint vDen, uint aw, uint ah, uint tw, uint th, uint videoStandard, uint scan) {
      var m = Mode(2, id, low, high);
      m.targetMode = new VIDEO_SIGNAL_INFO {
        pixelRate = pixelRate, hSyncFreq = new RATIONAL { Numerator = hNum, Denominator = hDen },
        vSyncFreq = new RATIONAL { Numerator = vNum, Denominator = vDen },
        activeSize = new REGION2D { cx = aw, cy = ah }, totalSize = new REGION2D { cx = tw, cy = th },
        videoStandard = videoStandard, scanLineOrdering = scan
      };
      return m;
    }

    public static MODE_INFO MakeSourceMode(uint id, uint low, int high, uint w, uint h, uint format, int x, int y) {
      var m = Mode(1, id, low, high);
      m.sourceMode = new SOURCE_MODE { width = w, height = h, pixelFormat = format, position = new POINTL { x = x, y = y } };
      return m;
    }

    public static MODE_INFO MakeDesktopMode(uint id, uint low, int high, int sx, int sy,
        int rl, int rt, int rr, int rb, int cl, int ct, int cr, int cb) {
      var m = Mode(3, id, low, high);
      m.desktopImageInfo = new DESKTOP_IMAGE_INFO {
        pathSourceSize = new POINTL { x = sx, y = sy },
        desktopImageRegion = new RECTL { left = rl, top = rt, right = rr, bottom = rb },
        desktopImageClip = new RECTL { left = cl, top = ct, right = cr, bottom = cb }
      };
      return m;
    }
  }
}
'@
}

function Get-MonitorSwitchDisplayInfo {
    [MonitorSwitchCcd.Config]::Query().GetDisplays()
}

function Get-MonitorSwitchDisplayHdr {
    [CmdletBinding()]
    param([int[]]$DisplayId, [switch]$Global)

    if ($Global) {
        $auto = $false
        $gpu = Get-ItemProperty -LiteralPath 'Registry::HKEY_CURRENT_USER\Software\Microsoft\DirectX\UserGpuPreferences' `
            -Name DirectXUserGlobalSettings -ErrorAction SilentlyContinue
        if ($gpu -and $gpu.DirectXUserGlobalSettings -match 'AutoHDREnable=(\d)') { $auto = $Matches[1] -ne '0' }
        $video = Get-ItemProperty -LiteralPath 'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\VideoSettings' `
            -Name EnableHDRForPlayback -ErrorAction SilentlyContinue
        $playback = [bool]($video -and $video.EnableHDRForPlayback)
        return [pscustomobject]@{ AutoHDREnabled = $auto; HDRPlaybackEnabled = $playback }
    }

    $config = [MonitorSwitchCcd.Config]::Query()
    foreach ($id in $DisplayId) { $config.GetHdr($id) }
}

function Disable-MonitorSwitchDisplayHdr {
    param([Parameter(Mandatory)][int[]]$DisplayId)
    $config = [MonitorSwitchCcd.Config]::Query()
    foreach ($id in $DisplayId) { $config.DisableHdr($id) }
}

function Disable-MonitorSwitchHdrPlayback {
    $path = 'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\VideoSettings'
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -LiteralPath $path -Name EnableHDRForPlayback -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
}

function ConvertTo-MonitorSwitchSnapshot {
    param([Parameter(Mandatory)][MonitorSwitchCcd.Config]$Config)
    [ordered]@{
        Version     = 1
        Available   = @($Config.Available)
        DevicePaths = @($Config.DevicePaths)
        Paths       = $Config.PathsBase64()
        Modes       = $Config.ModesBase64()
    } | ConvertTo-Json
}

function Export-MonitorSwitchBaselineConfig {
    param([Parameter(Mandatory)][string]$Path)
    $json = ConvertTo-MonitorSwitchSnapshot -Config ([MonitorSwitchCcd.Config]::Query())
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Import-MonitorSwitchSnapshot {
    param([Parameter(Mandatory)][string]$Path)
    $s = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($s.Version -ne 1) { throw "Unsupported snapshot version in $Path." }
    [MonitorSwitchCcd.Config]::FromSnapshot($s.Paths, $s.Modes, [int[]]@($s.Available), [string[]]@($s.DevicePaths))
}

function ConvertFrom-MonitorSwitchLegacyBaseline {
    <#
    .SYNOPSIS
        Rebuild a snapshot from a DisplayConfig-era baseline.xml without that module.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $legacy = Import-Clixml -LiteralPath $Path
    $paths = foreach ($p in $legacy.PathArray) {
        $s = $p.sourceInfo; $t = $p.targetInfo
        [MonitorSwitchCcd.Config]::MakePath(
            [uint32]$s.adapterId.LowPart, [int]$s.adapterId.HighPart, [uint32]$s.id, [uint32]$s.modeInfoIdx, [uint32][long]$s.statusFlags,
            [uint32]$t.adapterId.LowPart, [int]$t.adapterId.HighPart, [uint32]$t.id, [uint32]$t.modeInfoIdx,
            [uint32][long]$t.outputTechnology, [uint32][long]$t.rotation, [uint32][long]$t.scaling,
            [uint32]$t.refreshRate.Numerator, [uint32]$t.refreshRate.Denominator, [uint32][long]$t.scanlineOrdering,
            [bool]$t.targetAvailable, [uint32][long]$t.statusFlags, [uint32][long]$p.flags)
    }
    $modes = foreach ($m in $legacy.ModeArray) {
        $lo = [uint32]$m.adapterId.LowPart; $hi = [int]$m.adapterId.HighPart; $id = [uint32]$m.id
        switch ([long]$m.infoType) {
            1 {
                $v = $m.modeInfo.sourceMode
                [MonitorSwitchCcd.Config]::MakeSourceMode($id, $lo, $hi, [uint32]$v.width, [uint32]$v.height,
                    [uint32][long]$v.pixelFormat, [int]$v.position.x, [int]$v.position.y)
            }
            2 {
                $v = $m.modeInfo.targetMode.targetVideoSignalInfo
                [MonitorSwitchCcd.Config]::MakeTargetMode($id, $lo, $hi, [uint64]$v.pixelRate,
                    [uint32]$v.hSyncFreq.Numerator, [uint32]$v.hSyncFreq.Denominator,
                    [uint32]$v.vSyncFreq.Numerator, [uint32]$v.vSyncFreq.Denominator,
                    [uint32]$v.activeSize.cx, [uint32]$v.activeSize.cy, [uint32]$v.totalSize.cx, [uint32]$v.totalSize.cy,
                    [uint32]$v.videoStandardRaw, [uint32][long]$v.scanLineOrdering)
            }
            3 {
                $v = $m.modeInfo.desktopImageInfo
                $r = $v.desktopImageRegion; $c = $v.desktopImageClip
                [MonitorSwitchCcd.Config]::MakeDesktopMode($id, $lo, $hi, [int]$v.pathSourceSize.x, [int]$v.pathSourceSize.y,
                    [int]$r.left, [int]$r.top, [int]$r.right, [int]$r.bottom, [int]$c.left, [int]$c.top, [int]$c.right, [int]$c.bottom)
            }
            default { throw "Unknown mode type in $Path." }
        }
    }
    $config = [MonitorSwitchCcd.Config]::new()
    $config.Paths = [MonitorSwitchCcd.PATH_INFO[]]@($paths)
    $config.Modes = [MonitorSwitchCcd.MODE_INFO[]]@($modes)
    $config.Available = [int[]]@($legacy.AvailablePathIndexes)
    $config.DevicePaths = [string[]]@($legacy.AvailablePathNames | ForEach-Object { $_.monitorDevicePath })
    $config
}

function Test-MonitorSwitchBaseline {
    $dir = Get-MonitorSwitchStateDir
    (Test-Path (Join-Path $dir 'baseline.json')) -or (Test-Path (Join-Path $dir 'baseline.xml'))
}

function Import-MonitorSwitchBaselineConfig {
    <#
    .SYNOPSIS
        Load the baseline snapshot, migrating a legacy baseline.xml on first use.
    #>
    $dir = Get-MonitorSwitchStateDir
    $json = Join-Path $dir 'baseline.json'
    if (Test-Path -LiteralPath $json) { return Import-MonitorSwitchSnapshot -Path $json }

    $legacy = Join-Path $dir 'baseline.xml'
    if (-not (Test-Path -LiteralPath $legacy)) {
        throw 'No baseline snapshot. Arrange your monitors, then run: monitor-switch capture'
    }
    $config = ConvertFrom-MonitorSwitchLegacyBaseline -Path $legacy
    $positions = Join-Path $dir 'positions.json'
    if (Test-Path -LiteralPath $positions) {
        $saved = @(Get-Content -LiteralPath $positions -Raw | ConvertFrom-Json)
        foreach ($d in $saved) {
            if ($d.DisplayId -lt 1 -or $d.DisplayId -gt $config.DevicePaths.Count -or
                $config.DevicePaths[$d.DisplayId - 1] -ne $d.DevicePath) {
                throw 'baseline.xml and positions.json disagree. Arrange all connected panels and run monitor-switch capture.'
            }
        }
    }
    [System.IO.File]::WriteAllText($json, (ConvertTo-MonitorSwitchSnapshot -Config $config), [System.Text.UTF8Encoding]::new($false))
    $config
}

function Invoke-MonitorSwitchLayout {
    param([Parameter(Mandatory)][MonitorSwitchCcd.Config]$Config, [switch]$AllowChanges)
    $Config.UpdateAdapterIds()
    $Config.Apply([bool]$AllowChanges)
}
