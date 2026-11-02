using Forms = System.Windows.Forms;

namespace Ledge;

/// <summary>Ledge's icon in the notification area, with its menu. It's how you quit, since the island never takes focus.</summary>
sealed class Tray : IDisposable
{
    readonly Forms.NotifyIcon icon;

    public Tray(IslandWindow island)
    {
        var startAtLogin = new Forms.ToolStripMenuItem("Start Ledge when you sign in") { CheckOnClick = true };
        startAtLogin.Click += (_, _) => StartAtLogin.IsOn = startAtLogin.Checked;
        var menu = new Forms.ContextMenuStrip();
        menu.Opening += (_, _) => startAtLogin.Checked = StartAtLogin.IsOn; // setup can change it too
        menu.Items.Add("Change what Ledge shows…", null, (_, _) => island.StartSetup());
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

    public void Dispose()
    {
        icon.Visible = false;
        icon.Dispose();
    }
}
