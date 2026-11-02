using System.Windows;
using System.Windows.Threading;
using Velopack;
using Velopack.Sources;

namespace Ledge;

/// <summary>An installed Ledge keeps itself current from GitHub Releases. A copy run straight from a
/// download (not installed) never updates itself.</summary>
sealed class Updates
{
    // Mac releases share the repo; they have no releases.win.json, so they're skipped.
    readonly UpdateManager manager = new(new GithubSource("https://github.com/notsocj/ledge", null, false));
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromHours(6) };
    UpdateInfo? ready;
    bool restart;

    /// <summary>A new version is downloaded and goes in when Ledge restarts or quits.</summary>
    public event Action<string>? Ready;

    public void Start()
    {
        if (!manager.IsInstalled) return;
        timer.Tick += async (_, _) => await Check();
        timer.Start();
        _ = Check();
    }

    async Task Check()
    {
        if (ready is not null) return;
        try
        {
            var update = await manager.CheckForUpdatesAsync();
            if (update is null) return;
            await manager.DownloadUpdatesAsync(update);
            ready = update;
            Ready?.Invoke(update.TargetFullRelease.Version.ToString());
        }
        catch
        {
            // Offline, or GitHub didn't answer: the next check tries again.
        }
    }

    public void Restart()
    {
        restart = true;
        Application.Current.Shutdown();
    }

    /// <summary>Called as Ledge quits: the installer waits for it to close, then swaps in the new version.</summary>
    public void ApplyOnExit()
    {
        if (ready is not null) manager.WaitExitThenApplyUpdates(ready.TargetFullRelease, true, restart, []);
    }
}
