if (-not ('MonitorSwitch.Windows.DisplayModes' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace MonitorSwitch.Windows {
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

  public static class DisplayModes {
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

    public static List<DisplayMode> Query(bool includeSupportedRates) {
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
        if (includeSupportedRates) {
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

}
'@
}
