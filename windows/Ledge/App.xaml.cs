using System.IO;
using System.Windows;
using Velopack;

namespace Ledge;

public partial class App : Application
{
    Mutex? running;
    Tray? tray;
    Updates? updates;

    [STAThread]
    static void Main()
    {
        // The installer runs Ledge with its own arguments while installing, updating and uninstalling;
        // Run() handles those and exits. Otherwise it returns at once.
        VelopackApp.Build().OnBeforeUninstallFastCallback(_ => Uninstalling()).Run();
        var app = new App();
        app.InitializeComponent();
        app.Run();
    }

    /// <summary>Leaves nothing pointing at a Ledge that's gone: no sign-in entry, no agent hooks.</summary>
    static void Uninstalling()
    {
        StartAtLogin.IsOn = false;
        var agents = new AgentAlerts();
        agents.Refresh();
        if (agents.Claude == AgentAlerts.Status.Connected) agents.Disconnect(AgentAlerts.Agent.Claude);
        if (agents.Codex == AgentAlerts.Status.Connected) agents.Disconnect(AgentAlerts.Agent.Codex);
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        // A coding agent's hook started this copy: hand the event to the running Ledge and quit.
        if (e.Args is ["--agent", ..])
        {
            AgentAlerts.Forward(e.Args);
            Shutdown();
            return;
        }
        // Renders the island's pages to PNGs for design review, then quits. See Snapshots.cs.
        if (e.Args is ["--snapshot", var folder])
        {
            RunPreview(folder, Snapshots.Run);
            return;
        }
        // Uses only the production notification view and invented content, before live services start.
        if (e.Args is ["--notification-preview", var notificationFolder])
        {
            RunPreview(notificationFolder, path => NotificationSnapshots.Run(path));
            return;
        }
        // One Ledge at a time: starting it again (say, from the Start menu while it's already running) just exits.
        running = new Mutex(true, @"Local\Ledge", out var first);
        if (!first)
        {
            Shutdown();
            return;
        }
        base.OnStartup(e);
        var island = new IslandWindow();
        MainWindow = island;
        island.Show();
        updates = new Updates();
        tray = new Tray(island, updates);
        updates.Start();
    }

    /// <summary>A WinExe has no attached console in CI, so retain the actual render failure
    /// beside any completed preview frames while still returning a failing process exit code.</summary>
    void RunPreview(string folder, Action<string> render)
    {
        try
        {
            Directory.CreateDirectory(folder);
            File.Delete(Path.Combine(folder, "preview-error.txt"));
            render(folder);
            Shutdown();
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(error);
            try
            {
                Directory.CreateDirectory(folder);
                File.WriteAllText(Path.Combine(folder, "preview-error.txt"), error.ToString());
            }
            catch (Exception logError)
            {
                Console.Error.WriteLine($"Could not write preview-error.txt: {logError}");
            }
            Shutdown(1);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        tray?.Dispose();
        running?.Dispose();
        updates?.ApplyOnExit();
        base.OnExit(e);
    }
}
