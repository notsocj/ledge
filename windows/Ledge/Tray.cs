using Microsoft.Win32;
using Forms = System.Windows.Forms;

namespace Ledge;

/// <summary>Ledge's icon in the notification area, with its menu. It's how you quit, since the island never takes focus.</summary>
sealed class Tray : IDisposable
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    readonly Forms.NotifyIcon icon;

    public Tray(IslandWindow island)
    {
        var startAtLogin = new Forms.ToolStripMenuItem("Start Ledge when you sign in") { Checked = StartsAtLogin, CheckOnClick = true };
        startAtLogin.CheckedChanged += (_, _) => SetStartsAtLogin(startAtLogin.Checked);
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Show a test alert", null, (_, _) => island.ShowBanner("Test alert", "Ledge is running"));
        menu.Items.Add(startAtLogin);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit Ledge", null, (_, _) => System.Windows.Application.Current.Shutdown());

        using var stream = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/Assets/Ledge.ico")).Stream;
        icon = new Forms.NotifyIcon
        {
            Icon = new System.Drawing.Icon(stream, Forms.SystemInformation.SmallIconSize),
            Text = "Ledge",
            ContextMenuStrip = menu,
            Visible = true,
        };
    }

    static bool StartsAtLogin
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue("Ledge") is string;
        }
    }

    static void SetStartsAtLogin(bool on)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (on) key.SetValue("Ledge", $"\"{Environment.ProcessPath}\"");
        else key.DeleteValue("Ledge", throwOnMissingValue: false);
    }

    public void Dispose()
    {
        icon.Visible = false;
        icon.Dispose();
    }
}
