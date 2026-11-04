using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
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
        Tabs.Children.Clear();
        Tabs.Children.Add(HomeTab);
        foreach (var (tool, (tab, _)) in pages)
        {
            if (!settings.IsOn(tool) && tab.IsChecked == true) HomeTab.IsChecked = true;
        }
        foreach (var tool in settings.Layout.Tabs.Where(tool => settings.IsOn(tool) && pages.ContainsKey(tool))) Tabs.Children.Add(pages[tool].Tab);
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
    }

    /// <summary>Switches to a tool's tab, as when files are dragged onto the island.</summary>
    public void ShowTab(Tool tool)
    {
        if (pages.TryGetValue(tool, out var page) && Tabs.Children.Contains(page.Tab)) page.Tab.IsChecked = true;
    }

    // Now playing

    public void RefreshMedia()
    {
        var media = tools.NowPlaying;
        var on = settings.IsOn(Tool.Media);
        Playing.Visibility = on && media.HasMedia ? Visibility.Visible : Visibility.Collapsed;
        NothingPlaying.Visibility = on && !media.HasMedia ? Visibility.Visible : Visibility.Collapsed;
        ToolsAbove.Visibility = on || Tabs.Children.Count < 2 ? Visibility.Collapsed : Visibility.Visible;
        SongTitle.Text = media.Title;
        SongArtist.Text = media.Artist;
        PlayPauseGlyph.Text = media.IsPlaying ? "" : "";
        Artwork.Background = media.Artwork is { } art ? new ImageBrush(art) { Stretch = Stretch.UniformToFill } : (Brush)FindResource("Well");
        ArtworkGlyph.Visibility = media.Artwork is null ? Visibility.Visible : Visibility.Collapsed;
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
