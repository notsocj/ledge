using System.Runtime.InteropServices;

namespace Ledge;

/// <summary>The few Win32 calls WPF doesn't cover.</summary>
static partial class Native
{
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_TRANSPARENT = 0x20; // a layered notification passes mouse input to underlying apps
    public const int WS_EX_TOOLWINDOW = 0x80; // keeps the island out of Alt+Tab
    public const int WS_EX_NOACTIVATE = 0x08000000; // clicking the island never takes focus from your app

    public static readonly nint HWND_TOPMOST = -1;
    public const uint SWP_NOACTIVATE = 0x10;

    const uint MONITOR_DEFAULTTOPRIMARY = 1;
    const int MDT_EFFECTIVE_DPI = 0;

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    struct MONITORINFO
    {
        public int Size;
        public RECT Monitor, Work;
        public uint Flags;
    }

    [LibraryImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    public static partial nint GetWindowLongPtr(nint hwnd, int index);

    [LibraryImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    public static partial nint SetWindowLongPtr(nint hwnd, int index, nint value);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool SetWindowPos(nint hwnd, nint after, int x, int y, int width, int height, uint flags);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool GetCursorPos(out POINT point);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool GetWindowRect(nint hwnd, out RECT rect);

    [LibraryImport("user32.dll")]
    private static partial nint MonitorFromPoint(POINT point, uint flags);

    [LibraryImport("user32.dll", EntryPoint = "GetMonitorInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetMonitorInfo(nint monitor, ref MONITORINFO info);

    [LibraryImport("shcore.dll")]
    private static partial int GetDpiForMonitor(nint monitor, int type, out uint dpiX, out uint dpiY);

    [LibraryImport("shell32.dll")]
    private static partial int SHQueryUserNotificationState(out int state);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool AddClipboardFormatListener(nint hwnd);

    [LibraryImport("kernel32.dll")]
    public static partial uint SetThreadExecutionState(uint flags);

    [LibraryImport("iphlpapi.dll")]
    public static partial uint GetExtendedTcpTable(nint table, ref int size, int sort, int addressFamily, int tableClass, uint reserved);

    [LibraryImport("user32.dll")]
    private static partial int GetSystemMetrics(int index);

    [LibraryImport("user32.dll")]
    private static partial nint GetDC(nint hwnd);

    [LibraryImport("user32.dll")]
    private static partial int ReleaseDC(nint hwnd, nint dc);

    [LibraryImport("gdi32.dll")]
    private static partial uint GetPixel(nint dc, int x, int y);

    /// <summary>Every monitor together, in screen pixels.</summary>
    public static (int Left, int Top, int Width, int Height) VirtualScreen() =>
        (GetSystemMetrics(76), GetSystemMetrics(77), GetSystemMetrics(78), GetSystemMetrics(79));

    /// <summary>The color of one screen pixel. Layered windows, like Ledge's own, aren't part of the read.</summary>
    public static System.Windows.Media.Color ScreenColor(int x, int y)
    {
        var dc = GetDC(0);
        try
        {
            var bgr = GetPixel(dc, x, y);
            return System.Windows.Media.Color.FromRgb((byte)bgr, (byte)(bgr >> 8), (byte)(bgr >> 16));
        }
        finally
        {
            ReleaseDC(0, dc);
        }
    }

    /// <summary>The primary monitor's usable area (minus a taskbar docked at the top) and its scale.</summary>
    public static (RECT Work, double Scale) PrimaryMonitor()
    {
        var monitor = MonitorFromPoint(new POINT(), MONITOR_DEFAULTTOPRIMARY);
        var info = new MONITORINFO { Size = Marshal.SizeOf<MONITORINFO>() };
        GetMonitorInfo(monitor, ref info);
        return GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, out var dpi, out _) == 0
            ? (info.Work, dpi / 96.0)
            : (info.Work, 1);
    }

    /// <summary>True while a full-screen app, game or presentation is up, when the island should get out of the way.</summary>
    public static bool FullScreenAppRunning()
    {
        // 2: full-screen app ("busy"), 3: Direct3D full screen, 4: presentation mode.
        return SHQueryUserNotificationState(out var state) == 0 && state is 2 or 3 or 4;
    }
}
