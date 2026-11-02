using System.Diagnostics;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Microsoft.Win32;

namespace Ledge;

public partial class IslandWindow : Window
{
    static readonly Size ClosedSize = new(180, 32), WingsSize = new(250, 32), BannerSize = new(380, 32), OpenSize = new(560, 220),
        SetupSize = new(560, 290);
    /// <summary>The open island's corner. Closed, the corner is half the height, which makes it a pill.</summary>
    const double OpenCorner = 28;

    readonly Tools tools;
    Settings settings = Settings.Load(Settings.DefaultPath);
    readonly Spring width = new(ClosedSize.Width), height = new(ClosedSize.Height);
    readonly HoverIntent hover = new();
    readonly Stopwatch clock = Stopwatch.StartNew();
    readonly DispatcherTimer pointerTimer = new(DispatcherPriority.Input) { Interval = TimeSpan.FromMilliseconds(100) };
    readonly DispatcherTimer fullScreenTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    readonly DispatcherTimer batteryTimer = new() { Interval = TimeSpan.FromSeconds(30) };
    readonly DispatcherTimer countdownTimer = new() { Interval = TimeSpan.FromMilliseconds(250) };
    readonly DispatcherTimer bannerTimer = new();
    readonly Dictionary<UIElement, bool> shown = [];
    TimeSpan lastFrame;
    bool animating, expanded, hasWings, settingUp;
    /// <summary>Top of the usable screen, in screen pixels; below a taskbar docked at the top.</summary>
    double screenTop;

    public Tools Tools => tools;

    public IslandWindow()
    {
        InitializeComponent();
        tools = new Tools(Dispatcher);
        OpenView.Attach(tools, settings);
        Setup.Finished += FinishSetup;
        Apply();
        ContentRendered += (_, _) =>
        {
            if (!settings.SetupDone) StartSetup();
        };

        SourceInitialized += (_, _) =>
        {
            MakeUnobtrusive();
            Place();
            tools.Clipboard.Listen(Handle);
        };
        ApplyToolSwitches();

        // Files dragged onto the island go on the shelf; it opens on the shelf to show where they'll land.
        Island.AllowDrop = true;
        Island.DragEnter += (_, e) =>
        {
            if (!AcceptsDrop(e)) return;
            SetExpanded(true);
            OpenView.ShowTab(Tool.Shelf);
        };
        Island.DragOver += (_, e) =>
        {
            e.Effects = AcceptsDrop(e) ? DragDropEffects.Link : DragDropEffects.None;
            e.Handled = true;
        };
        Island.Drop += (_, e) =>
        {
            if (!AcceptsDrop(e) || e.Data.GetData(DataFormats.FileDrop) is not string[] files) return;
            var added = tools.Shelf.Add(files);
            ShowBanner("Shelf", added == 1 ? "1 file added" : $"{added} files added");
        };
        DpiChanged += (_, _) => Place();
        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
        SystemEvents.PowerModeChanged += OnPowerModeChanged;
        Closed += (_, _) =>
        {
            SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
            SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        };
        Island.MouseLeftButtonUp += (_, _) => SetExpanded(true); // touch screens have no hover: a tap opens it

        pointerTimer.Tick += (_, _) => FollowPointer();
        pointerTimer.Start();
        fullScreenTimer.Tick += (_, _) => GetOutOfFullScreenApps();
        fullScreenTimer.Start();
        bannerTimer.Tick += (_, _) => EndBanner();

        tools.NowPlaying.Changed += () =>
        {
            OpenView.RefreshMedia();
            RefreshWings();
        };
        _ = tools.NowPlaying.StartAsync();

        tools.Battery.Changed += OpenView.RefreshBattery;
        tools.Battery.Alert += (title, detail) => ShowBanner(title, detail);
        batteryTimer.Tick += (_, _) => tools.Battery.Check();
        batteryTimer.Start();
        tools.Battery.Check();

        tools.Agents.FollowIfMoved();
        tools.Agents.Event += (agent, waiting, project) =>
        {
            if (!settings.IsOn(Tool.AgentAlerts)) return;
            var name = agent == AgentAlerts.Agent.Claude ? "Claude" : "Codex";
            ShowBanner(project.Length > 0 ? $"{name} · {project}" : name, waiting ? "Needs you" : "Done", waiting ? 10 : 6,
                waiting ? (Brush)FindResource("Warning") : Brushes.White);
        };
        _ = tools.Agents.ListenAsync(Dispatcher);

        countdownTimer.Tick += (_, _) => TickCountdown();
        OpenView.Changed += () =>
        {
            if (tools.Countdown.IsRunning) countdownTimer.Start();
            TickCountdown();
        };
    }

    /// <summary>Slides an alert out of the closed island for a few seconds.</summary>
    public void ShowBanner(string title, string detail, double seconds = 2.5, Brush? detailColor = null)
    {
        if (expanded) return; // the open island already has the user's attention
        BannerTitle.Text = title;
        BannerDetail.Text = detail;
        BannerDetail.Foreground = detailColor ?? (Brush)FindResource("Graphite");
        bannerTimer.Stop();
        bannerTimer.Interval = TimeSpan.FromSeconds(seconds);
        bannerTimer.Start();
        UpdateShape();
    }

    void EndBanner()
    {
        bannerTimer.Stop();
        UpdateShape();
    }

    /// <summary>Opens the island on setup, and keeps it open until you finish.</summary>
    public void StartSetup()
    {
        Setup.Begin(settings);
        settingUp = true;
        if (expanded) UpdateShape();
        else SetExpanded(true);
    }

    bool AcceptsDrop(DragEventArgs e) => settings.IsOn(Tool.Shelf) && e.Data.GetDataPresent(DataFormats.FileDrop);

    /// <summary>Tools that work in the background stop when they're switched off.</summary>
    void ApplyToolSwitches()
    {
        tools.Clipboard.Enabled = settings.IsOn(Tool.Clipboard);
        if (!tools.Clipboard.Enabled) tools.Clipboard.Clear();
        if (!settings.IsOn(Tool.Shelf)) tools.Shelf.Clear();
    }

    void FinishSetup(Settings chosen)
    {
        settings = chosen;
        ApplyToolSwitches();
        try
        {
            settings.Save(Settings.DefaultPath);
        }
        catch (Exception)
        {
            // Couldn't write to %APPDATA%: keep the choices for this session, and setup shows again next time.
        }
        OpenView.Apply(settings);
        settingUp = false;
        SetExpanded(false);
        UpdateShape();
        RefreshWings();
    }

    void SetExpanded(bool open)
    {
        if (expanded == open || settingUp && !open) return;
        expanded = open;
        hover.Reset();
        bannerTimer.Stop();
        OpenView.SetOpen(open);
        UpdateShape();
    }

    /// <summary>The one place that decides the island's shape and which content shows.</summary>
    void UpdateShape()
    {
        var banner = bannerTimer.IsEnabled && !expanded;
        var wings = hasWings && !expanded && !banner;
        MoveTo(expanded ? (settingUp ? SetupSize : OpenSize) : banner ? BannerSize : wings ? WingsSize : ClosedSize);
        Fade(OpenView, expanded && !settingUp);
        OpenView.IsHitTestVisible = expanded && !settingUp;
        Fade(Setup, expanded && settingUp);
        Setup.IsHitTestVisible = expanded && settingUp;
        Fade(BannerContent, banner);
        Fade(Wings, wings);
    }

    // Closed island

    void TickCountdown()
    {
        var countdown = tools.Countdown;
        if (countdown.Tick()) ShowBanner("Timer done", $"{(int)countdown.Total.TotalMinutes} min");
        if (!countdown.IsRunning) countdownTimer.Stop(); // paused, cancelled or done: nothing to count
        OpenView.RefreshTimer();
        RefreshWings();
    }

    /// <summary>A timer takes the sides over what's playing; music shows only while it plays.</summary>
    void RefreshWings()
    {
        var countdown = tools.Countdown;
        var media = tools.NowPlaying;
        var art = !countdown.IsActive && media.IsPlaying ? media.Artwork : null;
        WingArt.Background = art is null ? null : new ImageBrush(art) { Stretch = Stretch.UniformToFill };
        WingGlyph.Text = countdown.IsActive ? "" : art is null ? "" : "";
        WingText.Text = countdown.IsActive ? Countdown.Format(countdown.Remaining) : "";
        WingRightGlyph.Visibility = !countdown.IsActive && media.IsPlaying ? Visibility.Visible : Visibility.Collapsed;
        var wings = countdown.IsActive || media.IsPlaying;
        if (wings == hasWings) return;
        hasWings = wings;
        UpdateShape();
    }

    void OnPowerModeChanged(object? sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.StatusChange) Dispatcher.BeginInvoke(new Action(tools.Battery.Check)); // plugged in or out
    }

    // Motion

    /// <summary>Opening and alerts get a spring with a little bounce; shrinking is quicker and doesn't bounce.</summary>
    void MoveTo(Size size)
    {
        if (size.Width == width.Target && size.Height == height.Target) return;
        if (!SystemParameters.ClientAreaAnimation) // Windows' "Animation effects" setting is off
        {
            width.Snap(size.Width);
            height.Snap(size.Height);
            Apply();
            return;
        }
        var growing = size.Width > width.Target || size.Height > height.Target;
        var (duration, bounce) = growing ? (0.5, 0.2) : (0.3, 0.0);
        width.Retarget(size.Width, duration, bounce);
        height.Retarget(size.Height, duration, bounce);
        if (animating) return;
        animating = true;
        lastFrame = TimeSpan.Zero;
        CompositionTarget.Rendering += OnFrame;
    }

    void OnFrame(object? sender, EventArgs e)
    {
        var now = ((RenderingEventArgs)e).RenderingTime;
        if (now == lastFrame) return; // Rendering can fire more than once per frame
        var seconds = lastFrame == TimeSpan.Zero ? 1.0 / 60 : (now - lastFrame).TotalSeconds;
        lastFrame = now;
        var moving = width.Step(seconds) | height.Step(seconds);
        Apply();
        if (moving) return;
        CompositionTarget.Rendering -= OnFrame;
        animating = false;
    }

    void Apply()
    {
        Island.Width = Math.Max(0, width.Value);
        Island.Height = Math.Max(0, height.Value);
        Island.CornerRadius = new CornerRadius(Math.Clamp(height.Value / 2, 0, OpenCorner));
    }

    /// <summary>Content fades in just after the island starts to grow, and out quickly as it shrinks.</summary>
    void Fade(UIElement element, bool show)
    {
        if (shown.TryGetValue(element, out var was) && was == show) return;
        shown[element] = show;
        element.BeginAnimation(OpacityProperty, new DoubleAnimation(show ? 1 : 0, TimeSpan.FromMilliseconds(show ? 200 : 100))
        {
            BeginTime = TimeSpan.FromMilliseconds(show ? 80 : 0),
            EasingFunction = new QuinticEase { EasingMode = EasingMode.EaseOut },
        });
    }

    // Pointer

    void FollowPointer()
    {
        if (!IsVisible || !Native.GetCursorPos(out var cursor)) return;
        var pointer = new Point(cursor.X, cursor.Y);
        var island = IslandRect();
        // The pointer is usually nowhere near the island: look less often until it comes close.
        var interval = TimeSpan.FromMilliseconds(expanded || pointer.Y < island.Bottom + 200 * hover.Scale ? 16 : 100);
        if (pointerTimer.Interval != interval) pointerTimer.Interval = interval;
        if (settingUp) return; // setup stays open until you finish it
        switch (hover.Update(pointer, clock.Elapsed.TotalSeconds, island, screenTop, expanded))
        {
            case HoverIntent.Decision.Open: SetExpanded(true); break;
            case HoverIntent.Decision.Close: SetExpanded(false); break;
        }
    }

    /// <summary>Where the island is right now, in screen pixels.</summary>
    Rect IslandRect()
    {
        var topLeft = Island.PointToScreen(new Point(0, 0));
        return new Rect(topLeft, new Size(Island.ActualWidth * hover.Scale, Island.ActualHeight * hover.Scale));
    }

    // Window

    nint Handle => new WindowInteropHelper(this).Handle;

    /// <summary>Out of Alt+Tab, and clicks on it never pull focus away from the app you're in.</summary>
    void MakeUnobtrusive()
    {
        var style = Native.GetWindowLongPtr(Handle, Native.GWL_EXSTYLE);
        Native.SetWindowLongPtr(Handle, Native.GWL_EXSTYLE, style | Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE);
    }

    /// <summary>Top centre of the primary monitor, in its own pixels, so mixed display scales line up.</summary>
    void Place()
    {
        var (work, scale) = Native.PrimaryMonitor();
        hover.Scale = scale;
        screenTop = work.Top;
        var pixelWidth = (int)Math.Round(Width * scale);
        var x = work.Left + (work.Right - work.Left - pixelWidth) / 2;
        Native.SetWindowPos(Handle, Native.HWND_TOPMOST, x, work.Top, pixelWidth, (int)Math.Round(Height * scale), Native.SWP_NOACTIVATE);
    }

    void OnDisplaySettingsChanged(object? sender, EventArgs e) => Dispatcher.BeginInvoke(new Action(Place));

    /// <summary>Hides during full-screen video, games and presentations, and comes back after.</summary>
    void GetOutOfFullScreenApps()
    {
        var hide = Native.FullScreenAppRunning();
        if (hide == !IsVisible) return;
        if (hide)
        {
            SetExpanded(false);
            Hide();
        }
        else
        {
            Show();
        }
    }
}
