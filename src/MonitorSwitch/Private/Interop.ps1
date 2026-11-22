# P/Invoke for both sides of a display:
#   MonitorSwitch.Display - user32 display modes (refresh rate), GPU side
#   MonitorSwitch.Ddc     - dxva2 DDC/CI (panel OSD), monitor side

if (-not ('MonitorSwitch.Display' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

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
    public int X, Y;
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
          X = cur.dmPositionX, Y = cur.dmPositionY,
          Width = cur.dmPelsWidth, Height = cur.dmPelsHeight, Bpp = cur.dmBitsPerPel,
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

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct PHYSICAL_MONITOR {
    public IntPtr handle;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string desc;
  }

  public static class Ddc {
    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int left, top, right, bottom; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct MONITORINFOEX {
      public int size; public RECT monitor, work; public uint flags;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string device;
    }

    delegate bool MonitorEnumProc(IntPtr hmon, IntPtr dc, IntPtr rect, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorEnumProc visit, IntPtr data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr hmon, ref MONITORINFOEX info);
    [DllImport("dxva2.dll")] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr h, out uint n);
    [DllImport("dxva2.dll")] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr h, uint n, [Out] PHYSICAL_MONITOR[] a);
    [DllImport("dxva2.dll")] static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte code, out uint type, out uint cur, out uint max);
    [DllImport("dxva2.dll")] static extern bool SetVCPFeature(IntPtr h, byte code, uint value);
    [DllImport("dxva2.dll")] static extern bool DestroyPhysicalMonitor(IntPtr h);

    // CCD names the GDI source; a desktop point can miss or hit a neighbour under DPI scaling.
    public static IntPtr Open(string device) {
      IntPtr match = IntPtr.Zero;
      int matches = 0;
      bool ok = EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr h, IntPtr dc, IntPtr rect, IntPtr data) {
        var info = new MONITORINFOEX { size = Marshal.SizeOf(typeof(MONITORINFOEX)) };
        if (GetMonitorInfo(h, ref info) && String.Equals(info.device, device, StringComparison.OrdinalIgnoreCase)) {
          match = h; matches++;
        }
        return true;
      }, IntPtr.Zero);
      if (!ok || matches != 1) return IntPtr.Zero;
      uint n;
      if (!GetNumberOfPhysicalMonitorsFromHMONITOR(match, out n) || n != 1) return IntPtr.Zero;
      var arr = new PHYSICAL_MONITOR[n];
      if (!GetPhysicalMonitorsFromHMONITOR(match, n, arr)) return IntPtr.Zero;
      return arr[0].handle;
    }

    public static void Close(IntPtr h) { if (h != IntPtr.Zero) DestroyPhysicalMonitor(h); }

    // Panels drop the occasional DDC/CI reply, so retry before calling it unsupported.
    public static bool TryGet(IntPtr h, byte code, out int current, out int max) {
      current = 0; max = 0;
      for (int attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) System.Threading.Thread.Sleep(40);
        uint type, cur, mx;
        if (GetVCPFeatureAndVCPFeatureReply(h, code, out type, out cur, out mx)) {
          current = (int)cur; max = (int)mx; return true;
        }
      }
      return false;
    }

    public static bool Set(IntPtr h, byte code, uint value) { return SetVCPFeature(h, code, value); }
  }
}
'@
}

# Picture settings only. Input source (0x60) must never be synced or treated as drift.
$script:VcpControls = @(
    [pscustomobject]@{ Code = 0x10; Label = 'Brightness' }
    [pscustomobject]@{ Code = 0x12; Label = 'Contrast' }
    [pscustomobject]@{ Code = 0x14; Label = 'ColorPreset' }
    [pscustomobject]@{ Code = 0x16; Label = 'RedGain' }
    [pscustomobject]@{ Code = 0x18; Label = 'GreenGain' }
    [pscustomobject]@{ Code = 0x1A; Label = 'BlueGain' }
    [pscustomobject]@{ Code = 0x87; Label = 'Sharpness' }
    [pscustomobject]@{ Code = 0xDC; Label = 'PictureMode' }
)
