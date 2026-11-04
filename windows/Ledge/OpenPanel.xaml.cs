using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace Ledge;

/// <summary>Everything Ledge shows. A tab's content is laid out at the open island's full size,
/// so it doesn't reflow while the island grows; the island clips it instead.</summary>
public partial class OpenPanel : UserControl
{
    Tools tools = null!;
    Settings settings = new();
    bool open, portsShown;
    IReadOnlyList<Ports.Listener> listeners = [];
    readonly DispatcherTimer portsTimer = new() { Interval = TimeSpan.FromSeconds(3) };
    /// <summary>Each tool with a tab of its own, and its page.</summary>
    readonly Dictionary<Tool, (RadioButton Tab, FrameworkElement Page)> pages;

    /// <summary>The tabs on show, in order: Home, then the tools your personas put first.</summary>
    readonly List<RadioButton> shownTabs = [];
    /// <summary>Where the selection pill is and how wide, each on a spring so it slides between tabs.</summary>
    readonly Spring pillX = new(0), pillWidth = new(0);
    readonly Stopwatch tabClock = new();
    TimeSpan lastTabFrame;
    bool tabsMoving;
    static readonly Duration TabMotion = TimeSpan.FromMilliseconds(260);
    static readonly IEasingFunction TabEase = new QuinticEase { EasingMode = EasingMode.EaseOut };

    /// <summary>Off for snapshots, which are drawn in one go.</summary>
    internal bool AnimateTabs { get; set; } = true;

    /// <summary>The user changed something the closed island shows too, like starting a timer.</summary>
    public event Action? Changed;

    public ColorPage ColorTabPage => ColorView;
    public CalendarPage CalendarTabPage => CalendarView;

    public OpenPanel()
    {
        InitializeComponent();
        portsTimer.Tick += async (_, _) => await RefreshPorts();
        pages = new()
        {
            [Tool.Timer] = (TimerTab, TimerPage),
            [Tool.Ports] = (PortsTab, PortsPage),
            [Tool.Clipboard] = (ClipboardTab, ClipboardView),
            [Tool.Shelf] = (ShelfTab, ShelfView),
            [Tool.ColorPicker] = (ColorTab, ColorView),
            [Tool.Calendar] = (CalendarTab, CalendarView),
        };
        foreach (var (tool, (tab, _)) in pages) tab.Tag = tool.Glyph(); // the same icons as setup's tool chips
        // The first layout, when the pill can first be placed: until then the tabs have no size.
        Header.SizeChanged += (_, _) =>
        {
            if (!tabsMoving) SettleTabs();
        };
    }

    public void Attach(Tools tools, Settings settings)
    {
        this.tools = tools;
        ClipboardView.Attach(tools.Clipboard);
        ShelfView.Attach(tools.Shelf);
        ColorView.Attach(tools.ColorPicker);
        CalendarView.Attach(tools.Calendar, settings.CalendarLink is not null);
        tools.Calendar.Changed += RefreshNextMeeting;
        HomeTab.IsChecked = true;
        Apply(settings);
        RefreshBattery();
        RefreshTimer();
    }

    /// <summary>Arranges the tabs and Home around what's on, most important first.</summary>
    public void Apply(Settings settings)
    {
        this.settings = settings;
        foreach (var (tool, (tab, _)) in pages)
        {
            if (!settings.IsOn(tool) && tab.IsChecked == true) HomeTab.IsChecked = true;
        }
        shownTabs.Clear();
        shownTabs.Add(HomeTab);
        shownTabs.AddRange(settings.Layout.Tabs.Where(tool => settings.IsOn(tool) && pages.ContainsKey(tool)).Select(tool => pages[tool].Tab));
        // Split down the middle, as the Mac splits them around the notch. Home leads on the left, and the
        // left side takes the extra tab when there's an odd number.
        LeftTabs.Children.Clear();
        RightTabs.Children.Clear();
        var left = (shownTabs.Count + 1) / 2;
        for (var index = 0; index < shownTabs.Count; index++) (index < left ? LeftTabs : RightTabs).Children.Add(shownTabs[index]);
        RightTrack.Visibility = RightTabs.Children.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        SlideTabs(animate: false);
        if (!settings.IsOn(Tool.KeepAwake) && tools.KeepAwake.IsOn) KeepAwake_Click(this, new RoutedEventArgs());
        KeepAwakeToggle.Visibility = settings.IsOn(Tool.KeepAwake) ? Visibility.Visible : Visibility.Collapsed;
        CalendarView.SetHasLink(settings.CalendarLink is not null);
        RefreshMedia();
        RefreshNextMeeting();
    }

    /// <summary>Ports are only looked up while you can see them.</summary>
    public void SetOpen(bool open)
    {
        this.open = open;
        _ = UpdatePortsWatch();
    }

    // Tabs

    void Tab_Checked(object sender, RoutedEventArgs e)
    {
        if (tools is null) return; // during InitializeComponent
        HomePage.Visibility = HomeTab.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        foreach (var (tab, page) in pages.Values) page.Visibility = tab.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        if (ShelfTab.IsChecked == true) tools.Shelf.Prune();
        _ = UpdatePortsWatch();
        SlideTabs(animate: true);
    }

    /// <summary>Slides the open tab's name open and the others' shut, and sends the pill after the open tab.
    /// Without animation (Windows' "Animation effects" off, or a snapshot) everything jumps into place.</summary>
    void SlideTabs(bool animate)
    {
        animate &= AnimateTabs && SystemParameters.ClientAreaAnimation;
        foreach (var tab in shownTabs)
        {
            tab.ApplyTemplate();
            if (tab.Template.FindName("LabelHost", tab) is not FrameworkElement host || tab.Template.FindName("Label", tab) is not FrameworkElement label) continue;
            var open = tab.IsChecked == true;
            label.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity)); // the name's natural width, with its gap
            var width = open ? label.DesiredSize.Width : 0;
            if (animate)
            {
                // From the width it has now (a settled open tab's is automatic, so there's no animated value to start from).
                var slide = new DoubleAnimation(host.ActualWidth, width, TabMotion) { EasingFunction = TabEase };
                if (open) slide.Completed += (_, _) =>
                {
                    if (tab.IsChecked == true) SizeToName(host); // a later switch may have closed it already
                };
                host.BeginAnimation(WidthProperty, slide);
                // Names fade in a little behind the slide, and out quickly, so they never look squashed.
                label.BeginAnimation(OpacityProperty, new DoubleAnimation(open ? 1 : 0, open ? TabMotion : TimeSpan.FromMilliseconds(120))
                {
                    BeginTime = open ? TimeSpan.FromMilliseconds(60) : TimeSpan.Zero,
                });
            }
            else
            {
                if (open) SizeToName(host);
                else
                {
                    host.BeginAnimation(WidthProperty, null);
                    host.Width = 0;
                }
                label.BeginAnimation(OpacityProperty, null);
                label.Opacity = open ? 1 : 0;
            }
        }
        if (!animate)
        {
            Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(SettleTabs)); // once the new widths are laid out
            return;
        }
        // Followed frame by frame: the open tab's width and place change while the names slide.
        tabClock.Restart();
        if (tabsMoving) return;
        tabsMoving = true;
        lastTabFrame = TimeSpan.Zero;
        CompositionTarget.Rendering += OnTabFrame;
    }

    /// <summary>Once its name has slid open, the open tab sizes to its name itself, so the measured width
    /// (taken before the font may have loaded) never clips it.</summary>
    static void SizeToName(FrameworkElement host)
    {
        host.BeginAnimation(WidthProperty, null);
        host.Width = double.NaN;
    }

    void OnTabFrame(object? sender, EventArgs e)
    {
        var now = ((RenderingEventArgs)e).RenderingTime;
        if (now == lastTabFrame) return; // Rendering can fire more than once per frame
        var seconds = lastTabFrame == TimeSpan.Zero ? 1.0 / 60 : (now - lastTabFrame).TotalSeconds;
        lastTabFrame = now;
        if (OpenTabBounds() is not { } target)
        {
            StopTabFrames();
            return;
        }
        if (pillWidth.Value == 0) // never placed: appear on the tab rather than grow from the corner
        {
            pillX.Snap(target.X);
            pillWidth.Snap(target.Width);
        }
        // A little bounce, like the island's own spring when it opens.
        pillX.Retarget(target.X, 0.4, 0.15);
        pillWidth.Retarget(target.Width, 0.4, 0.15);
        var moving = pillX.Step(seconds) | pillWidth.Step(seconds);
        PlacePill();
        if (moving || tabClock.Elapsed < TabMotion.TimeSpan + TimeSpan.FromMilliseconds(60)) return;
        StopTabFrames();
    }

    void StopTabFrames()
    {
        CompositionTarget.Rendering -= OnTabFrame;
        tabsMoving = false;
    }

    /// <summary>Puts the pill straight on the open tab. Snapshots call it once the panel is laid out.</summary>
    internal void SettleTabs()
    {
        if (OpenTabBounds() is not { } target) return;
        pillX.Snap(target.X);
        pillWidth.Snap(target.Width);
        PlacePill();
    }

    /// <summary>The open tab's box within the header, as it is this frame.</summary>
    Rect? OpenTabBounds()
    {
        var tab = shownTabs.FirstOrDefault(tab => tab.IsChecked == true);
        if (tab is null || !Header.IsAncestorOf(tab) || tab.ActualWidth == 0) return null;
        return tab.TransformToAncestor(Header).TransformBounds(new Rect(new Point(0, 0), tab.RenderSize));
    }

    void PlacePill()
    {
        Canvas.SetLeft(Selection, pillX.Value);
        Selection.Width = Math.Max(0, pillWidth.Value);
    }

    /// <summary>Switches to a tool's tab, as when files are dragged onto the island.</summary>
    public void ShowTab(Tool tool)
    {
        if (pages.TryGetValue(tool, out var page) && shownTabs.Contains(page.Tab)) page.Tab.IsChecked = true;
    }

    // Now playing

    public void RefreshMedia()
    {
        var media = tools.NowPlaying;
        var on = settings.IsOn(Tool.Media);
        Playing.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        PlaybackControls.Visibility = media.HasMedia ? Visibility.Visible : Visibility.Collapsed;
        MediaDetails.VerticalAlignment = media.HasMedia ? VerticalAlignment.Stretch : VerticalAlignment.Center;
        ToolsAbove.Visibility = on || shownTabs.Count < 2 ? Visibility.Collapsed : Visibility.Visible;
        SongTitle.Text = media.HasMedia ? media.Title : "Nothing playing";
        SongArtist.Text = media.HasMedia ? media.Artist : "Play music in any app";
        PlayPauseGlyph.Text = media.IsPlaying ? "" : "";
        PlayPauseButton.ToolTip = media.IsPlaying ? "Pause" : "Play";
        System.Windows.Automation.AutomationProperties.SetName(PlayPauseButton, media.IsPlaying ? "Pause" : "Play");
        Artwork.Background = media.Artwork is { } art ? new ImageBrush(art) { Stretch = Stretch.UniformToFill } : (Brush)FindResource("Well");
        ArtworkGlyph.Visibility = media.Artwork is null ? Visibility.Visible : Visibility.Collapsed;
        RefreshHomeLayout();
    }

    /// <summary>Use the spare room for music when Home has no status cards, instead of leaving an empty column.</summary>
    void RefreshHomeLayout()
    {
        var sidebar = NextMeetingCard.Visibility == Visibility.Visible || BatteryCard.Visibility == Visibility.Visible
            || KeepAwakeToggle.Visibility == Visibility.Visible;
        HomeSidebar.Visibility = sidebar ? Visibility.Visible : Visibility.Collapsed;
        HomeSidebarColumn.Width = new GridLength(sidebar ? 150 : 0);
        HomeGutter.Width = new GridLength(sidebar ? 24 : 0);
        var artworkSize = sidebar ? 112 : 120;
        Artwork.Width = Artwork.Height = Playing.Height = artworkSize;
    }

    void PlayPause_Click(object sender, RoutedEventArgs e) => _ = tools.NowPlaying.PlayPause();
    void Next_Click(object sender, RoutedEventArgs e) => _ = tools.NowPlaying.Next();
    void Previous_Click(object sender, RoutedEventArgs e) => _ = tools.NowPlaying.Previous();

    // Calendar

    /// <summary>Home's "next up" card: the next timed meeting today, if the calendar is on.</summary>
    public void RefreshNextMeeting()
    {
        var now = DateTime.Now;
        var next = settings.IsOn(Tool.Calendar)
            ? tools.Calendar.Meetings.FirstOrDefault(meeting => !meeting.AllDay && meeting.End > now && meeting.Start.Date == now.Date)
            : null;
        NextMeetingCard.Visibility = next is null ? Visibility.Collapsed : Visibility.Visible;
        RefreshHomeLayout();
        if (next is null) return;
        NextMeetingWhen.Text = next.Start <= now ? "Now" : $"Next at {next.Start:t}";
        NextMeetingTitle.Text = next.Title;
    }

    // Battery and keep awake

    public void RefreshBattery()
    {
        var battery = tools.Battery;
        BatteryCard.Visibility = battery.Percent is null ? Visibility.Collapsed : Visibility.Visible;
        BatteryText.Text = battery.Percent is { } percent ? (battery.OnPower ? $"{percent}%, plugged in" : $"{percent}%") : "";
        RefreshHomeLayout();
    }

    void KeepAwake_Click(object sender, RoutedEventArgs e)
    {
        tools.KeepAwake.Toggle();
        KeepAwakeToggle.IsChecked = tools.KeepAwake.IsOn;
        KeepAwakeText.Text = tools.KeepAwake.IsOn ? "Keeping awake" : "Keep awake";
    }

    // Timer

    public void RefreshTimer()
    {
        var countdown = tools.Countdown;
        TimerText.Text = Countdown.Format(countdown.IsActive ? countdown.Remaining : TimeSpan.Zero);
        TimerHint.Text = countdown.IsRunning ? $"{(int)countdown.Total.TotalMinutes} min timer" : countdown.IsActive ? "Paused" : "Pick a length to start.";
        TimerPresets.Visibility = countdown.IsActive ? Visibility.Collapsed : Visibility.Visible;
        TimerControls.Visibility = countdown.IsActive ? Visibility.Visible : Visibility.Collapsed;
        PauseResume.Content = countdown.IsRunning ? "Pause" : "Resume";
    }

    void Preset_Click(object sender, RoutedEventArgs e)
    {
        tools.Countdown.Start(int.Parse((string)((Button)sender).Tag));
        TimerChanged();
    }

    void PauseResume_Click(object sender, RoutedEventArgs e)
    {
        if (tools.Countdown.IsRunning) tools.Countdown.Pause();
        else tools.Countdown.Resume();
        TimerChanged();
    }

    void AddMinute_Click(object sender, RoutedEventArgs e)
    {
        tools.Countdown.AddMinute();
        TimerChanged();
    }

    void CancelTimer_Click(object sender, RoutedEventArgs e)
    {
        tools.Countdown.Cancel();
        TimerChanged();
    }

    void TimerChanged()
    {
        RefreshTimer();
        Changed?.Invoke();
    }

    // Ports

    async Task UpdatePortsWatch()
    {
        var watching = open && PortsTab.IsChecked == true;
        if (watching == portsTimer.IsEnabled) return;
        if (!watching)
        {
            portsTimer.Stop();
            return;
        }
        portsTimer.Start();
        await RefreshPorts();
    }

    async Task RefreshPorts()
    {
        var found = await Task.Run(Ports.Find);
        if (portsShown && found.SequenceEqual(listeners)) return; // rebuilding would lose a pending "Stop it?"
        ShowPorts(found);
    }

    /// <summary>Lists these servers. Snapshots call it with made-up ones.</summary>
    internal void ShowPorts(IReadOnlyList<Ports.Listener> found)
    {
        portsShown = true;
        listeners = found;
        PortsHeader.Text = found.Count == 1 ? "1 server on localhost" : $"{found.Count} servers on localhost";
        PortsList.Visibility = found.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        NoPorts.Visibility = found.Count > 0 ? Visibility.Collapsed : Visibility.Visible;
        PortRows.Children.Clear();
        foreach (var listener in found) PortRows.Children.Add(PortRow(listener));
    }

    UIElement PortRow(Ports.Listener listener)
    {
        var row = new Grid { Height = 32, Margin = new Thickness(10, 0, 6, 2) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(60) });
        row.ColumnDefinitions.Add(new ColumnDefinition());
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var dot = new Ellipse { Width = 6, Height = 6, Fill = (Brush)FindResource("Live"), Margin = new Thickness(0, 0, 10, 0), ToolTip = "Listening" };
        // The port is what you scan for, so it's the heavier of the two; the process name sits beside it, lighter.
        var port = new TextBlock { Text = $":{listener.Port}", Style = (Style)FindResource("TitleText"), VerticalAlignment = VerticalAlignment.Center };
        var name = new TextBlock { Text = listener.Name, Style = (Style)FindResource("BodyText"), TextWrapping = TextWrapping.NoWrap,
            TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
        var openButton = new Button { Style = (Style)FindResource("Icon"), Content = Glyph(""), ToolTip = $"Open localhost:{listener.Port} in your browser" };
        openButton.Click += (_, _) => Process.Start(new ProcessStartInfo($"http://localhost:{listener.Port}") { UseShellExecute = true });

        // Stopping ends someone's process, so it takes a second click to confirm.
        var stopButton = new Button { Style = (Style)FindResource("Icon"), Content = Glyph(""), ToolTip = "Stop this server" };
        var confirming = false;
        var reset = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
        reset.Tick += (_, _) =>
        {
            reset.Stop();
            confirming = false;
            stopButton.Style = (Style)FindResource("Icon");
            stopButton.Content = Glyph("");
        };
        stopButton.Click += async (_, _) =>
        {
            if (confirming)
            {
                reset.Stop();
                Ports.Stop(listener);
                await Task.Delay(400);
                await RefreshPorts();
                return;
            }
            confirming = true;
            stopButton.Style = (Style)FindResource("Pill");
            stopButton.Content = new TextBlock { Text = "Stop it?", Foreground = (Brush)FindResource("Warning") };
            reset.Start();
        };

        Grid.SetColumn(port, 1);
        Grid.SetColumn(name, 2);
        Grid.SetColumn(openButton, 3);
        Grid.SetColumn(stopButton, 4);
        foreach (UIElement child in new UIElement[] { dot, port, name, openButton, stopButton }) row.Children.Add(child);
        return new Border { Child = row, CornerRadius = new CornerRadius(10) };
    }

    static TextBlock Glyph(string glyph) => new() { Text = glyph, FontSize = 12, Style = (Style)Application.Current.FindResource("Glyph") };
}
