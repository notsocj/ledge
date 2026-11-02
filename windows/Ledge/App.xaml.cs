using System.Windows;

namespace Ledge;

public partial class App : Application
{
    Mutex? running;
    Tray? tray;

    protected override void OnStartup(StartupEventArgs e)
    {
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
        tray = new Tray(island);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        tray?.Dispose();
        running?.Dispose();
        base.OnExit(e);
    }
}
