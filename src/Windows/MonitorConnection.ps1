if (-not ('MonitorSwitch.Windows.MonitorConnection' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace MonitorSwitch.Windows {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct PHYSICAL_MONITOR {
    public IntPtr handle;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string desc;
  }

  public static class MonitorConnection {
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

    // Match the Windows source name, not a desktop point affected by DPI scaling.
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

    public static void Close(IntPtr h) {
      if (h != IntPtr.Zero) DestroyPhysicalMonitor(h);
    }

    public static bool TryReadSetting(IntPtr h, byte code, out int current, out int max) {
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

    public static bool WriteSetting(IntPtr h, byte code, uint value) {
      return SetVCPFeature(h, code, value);
    }
  }
}
'@
}
