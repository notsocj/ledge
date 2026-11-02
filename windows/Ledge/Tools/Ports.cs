using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Ledge;

/// <summary>What you've got listening on localhost (dev servers and the like), with Open and Stop.
/// Windows' own services and processes Ledge isn't allowed to look at are left out.</summary>
public static class Ports
{
    public sealed record Listener(int Port, int Pid, string Name);

    const int AF_INET = 2, AF_INET6 = 23, TCP_TABLE_OWNER_PID_LISTENER = 3, ERROR_INSUFFICIENT_BUFFER = 122;

    public static List<Listener> Find()
    {
        var pidByPort = new Dictionary<int, int>();
        // Row layouts of MIB_TCPROW_OWNER_PID and MIB_TCP6ROW_OWNER_PID: size, local port offset, pid offset.
        foreach (var (port, pid) in Read(AF_INET, 24, 8, 20).Concat(Read(AF_INET6, 56, 20, 52))) pidByPort.TryAdd(port, pid);
        var pathByPid = new Dictionary<int, string?>();
        var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var found = new List<Listener>();
        foreach (var (port, pid) in pidByPort)
        {
            if (!pathByPid.TryGetValue(pid, out var path)) pathByPid[pid] = path = ExecutablePath(pid);
            if (IsYours(port, path, windows)) found.Add(new(port, pid, Path.GetFileNameWithoutExtension(path!)));
        }
        return [.. found.OrderBy(listener => listener.Port)];
    }

    /// <summary>Your own program, below 49152 (the range Windows hands out for short-lived ports), and not part of Windows.</summary>
    public static bool IsYours(int port, string? path, string windowsFolder) =>
        port < 49152 && path is not null && !path.StartsWith(windowsFolder.TrimEnd('\\') + '\\', StringComparison.OrdinalIgnoreCase);

    /// <summary>Ports come in network byte order in the low 16 bits.</summary>
    public static int NetworkPort(int raw) => ((raw & 0xFF) << 8) | ((raw >> 8) & 0xFF);

    /// <summary>Ends the process, after the user has confirmed. Windows has no polite Ctrl-C for another program.</summary>
    public static void Stop(Listener listener)
    {
        try
        {
            using var process = Process.GetProcessById(listener.Pid);
            process.Kill();
        }
        catch (Exception) { } // already gone, or not ours to stop
    }

    static List<(int Port, int Pid)> Read(int family, int rowSize, int portOffset, int pidOffset)
    {
        for (var attempt = 0; attempt < 3; attempt++) // the table can grow between asking its size and reading it
        {
            var size = 0;
            Native.GetExtendedTcpTable(0, ref size, 0, family, TCP_TABLE_OWNER_PID_LISTENER, 0);
            var table = Marshal.AllocHGlobal(size);
            try
            {
                var result = Native.GetExtendedTcpTable(table, ref size, 0, family, TCP_TABLE_OWNER_PID_LISTENER, 0);
                if (result == ERROR_INSUFFICIENT_BUFFER) continue;
                if (result != 0) return [];
                var count = Marshal.ReadInt32(table);
                var rows = new List<(int, int)>(count);
                for (var i = 0; i < count; i++)
                {
                    var row = table + 4 + i * rowSize;
                    rows.Add((NetworkPort(Marshal.ReadInt32(row + portOffset)), Marshal.ReadInt32(row + pidOffset)));
                }
                return rows;
            }
            finally
            {
                Marshal.FreeHGlobal(table);
            }
        }
        return [];
    }

    static string? ExecutablePath(int pid)
    {
        if (pid is 0 or 4) return null; // the idle and System processes
        try
        {
            using var process = Process.GetProcessById(pid);
            return process.MainModule?.FileName;
        }
        catch (Exception)
        {
            return null; // another user's or an elevated process: not something you started
        }
    }
}
