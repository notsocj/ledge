using Microsoft.Win32;

namespace Ledge;

/// <summary>Notices when an app starts using the microphone or camera, from the same record Windows
/// keeps for its own privacy indicator (no permission needed to read it).</summary>
public sealed class InUse
{
    public enum Device { Microphone, Camera }

    const string Store = @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore";
    HashSet<(Device, string)>? known;

    /// <summary>An app started using a device.</summary>
    public event Action<Device, string>? Started;

    /// <summary>Call every couple of seconds. The first check only learns what's already in use.</summary>
    public void Check()
    {
        var now = new HashSet<(Device, string)>();
        foreach (var device in Enum.GetValues<Device>())
        {
            foreach (var app in AppsUsing(device == Device.Microphone ? "microphone" : "webcam")) now.Add((device, app));
        }
        if (known is not null)
        {
            foreach (var (device, app) in now.Except(known)) Started?.Invoke(device, app);
        }
        known = now;
    }

    public void Reset() => known = null;

    static IEnumerable<string> AppsUsing(string capability)
    {
        using var root = Registry.CurrentUser.OpenSubKey($@"{Store}\{capability}");
        if (root is null) yield break;
        foreach (var (key, name) in Apps(root))
        {
            using (key)
            {
                if (IsInUse(key.GetValue("LastUsedTimeStart"), key.GetValue("LastUsedTimeStop"))) yield return AppName(name);
            }
        }
    }

    /// <summary>Store apps sit directly under the capability; desktop apps under NonPackaged.</summary>
    static IEnumerable<(RegistryKey Key, string Name)> Apps(RegistryKey root)
    {
        foreach (var name in root.GetSubKeyNames())
        {
            if (name == "NonPackaged")
            {
                using var desktop = root.OpenSubKey(name);
                if (desktop is null) continue;
                foreach (var app in desktop.GetSubKeyNames())
                {
                    if (desktop.OpenSubKey(app) is { } key) yield return (key, app);
                }
            }
            else if (root.OpenSubKey(name) is { } key)
            {
                yield return (key, name);
            }
        }
    }

    /// <summary>In use: it has started, and hasn't stopped since (Windows writes 0 as the stop time while it's on).</summary>
    public static bool IsInUse(object? start, object? stop) => start is long started && started > 0 && stop is long stopped && stopped == 0;

    /// <summary>"C:#Program Files#Zoom#bin#Zoom.exe" → "Zoom"; "Microsoft.WindowsCamera_8wekyb3d8bbwe" → "WindowsCamera".</summary>
    public static string AppName(string key)
    {
        if (key.Contains('#')) return System.IO.Path.GetFileNameWithoutExtension(key[(key.LastIndexOf('#') + 1)..]);
        var family = key.Split('_')[0];
        return family[(family.LastIndexOf('.') + 1)..];
    }
}
