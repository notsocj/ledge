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
        menu.Items.Add(AgentsMenu(island));
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

    /// <summary>Connecting changes the agent's own settings file, so it only ever happens from here, when you ask.</summary>
    static Forms.ToolStripMenuItem AgentsMenu(IslandWindow island)
    {
        var agents = island.Tools.Agents;
        var menu = new Forms.ToolStripMenuItem("Coding agent alerts");
        foreach (var (agent, name) in new[] { (AgentAlerts.Agent.Claude, "Claude Code"), (AgentAlerts.Agent.Codex, "Codex") })
        {
            var item = new Forms.ToolStripMenuItem(name);
            item.Click += (_, _) =>
            {
                var connected = (agent == AgentAlerts.Agent.Claude ? agents.Claude : agents.Codex) == AgentAlerts.Status.Connected;
                if (connected) agents.Disconnect(agent);
                else agents.Connect(agent);
                island.ShowBanner(name, agents.LastError is null ? (connected ? "Disconnected" : "Connected") : "Couldn't change its settings");
            };
            menu.DropDownItems.Add(item);
        }
        menu.DropDownOpening += (_, _) =>
        {
            agents.Refresh();
            foreach (var (item, status) in new[] { (menu.DropDownItems[0], agents.Claude), (menu.DropDownItems[1], agents.Codex) })
            {
                var name = item == menu.DropDownItems[0] ? "Claude Code" : "Codex";
                ((Forms.ToolStripMenuItem)item).Checked = status == AgentAlerts.Status.Connected;
                item.Enabled = status is AgentAlerts.Status.Connected or AgentAlerts.Status.Disconnected;
                item.Text = status switch
                {
                    AgentAlerts.Status.NotInstalled => $"{name} (not installed)",
                    AgentAlerts.Status.Blocked => $"{name} (its notify setting can't be changed safely)",
                    _ => name,
                };
            }
        };
        return menu;
    }

    public void Dispose()
    {
        icon.Visible = false;
        icon.Dispose();
    }
}
