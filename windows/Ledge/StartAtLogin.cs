using Microsoft.Win32;

namespace Ledge;

/// <summary>Starting Ledge when you sign in, through your own Run key (no admin rights needed).</summary>
static class StartAtLogin
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public static bool IsOn
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue("Ledge") is string;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (value) key.SetValue("Ledge", $"\"{Environment.ProcessPath}\"");
            else key.DeleteValue("Ledge", throwOnMissingValue: false);
        }
    }
}
