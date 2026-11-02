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
    static readonly Size ClosedSize = new(180, 32), BannerSize = new(380, 32), OpenSize = new(560, 200);
    /// <summary>The open island's corner. Closed, the corner is half the height, which makes it a pill.</summary>
    const double OpenCorner = 28;

    readonly Spring width = new(ClosedSize.Width), height = new(ClosedSize.Height);
    readonly HoverIntent hover = new();
    readonly Stopwatch clock = Stopwatch.StartNew();
    readonly DispatcherTimer pointerTimer = new(DispatcherPriority.Input) { Interval = TimeSpan.FromMilliseconds(100) };
    readonly DispatcherTimer fullScreenTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    readonly DispatcherTimer bannerTimer = new();
    TimeSpan lastFrame;
    bool animating, expanded;
    /// <summary>Top of the usable screen, in screen pixels; below a taskbar docked at the top.</summary>
    double screenTop;

    public IslandWindow()
    {
        InitializeComponent();
        Apply();
        SourceInitialized += (_, _) =>
        {
            MakeUnobtrusive();
            Place();
        };
        DpiChanged += (_, _) => Place();
        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
        Closed += (_, _) => SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
        Island.MouseLeftButtonUp += (_, _) => SetExpanded(true); // touch screens have no hover: a tap opens it
        pointerTimer.Tick += (_, _) => FollowPointer();
        pointerTimer.Start();
        fullScreenTimer.Tick += (_, _) => GetOutOfFullScreenApps();
        fullScreenTimer.Start();
        bannerTimer.Tick += (_, _) => EndBanner();
    }

    /// <summary>Slides an alert out of the closed island for a few seconds.</summary>
    public void ShowBanner(string title, string detail, double seconds = 2.5)
    {
        if (expanded) return; // the open island already has the user's attention
        BannerTitle.Text = title;
        BannerDetail.Text = detail;
        MoveTo(BannerSize);
        Fade(BannerContent, true);
        bannerTimer.Stop();
        bannerTimer.Interval = TimeSpan.FromSeconds(seconds);
        bannerTimer.Start();
    }

    void EndBanner()
    {
        bannerTimer.Stop();
        Fade(BannerContent, false);
        if (!expanded) MoveTo(ClosedSize);
    }

    void SetExpanded(bool open)
    {
        if (expanded == open) return;
        expanded = open;
        hover.Reset();
        if (open && bannerTimer.IsEnabled) EndBanner();
        MoveTo(open ? OpenSize : ClosedSize);
        Fade(OpenContent, open);
    }

    // Motion

    /// <summary>Opening and alerts get a spring with a little bounce; shrinking is quicker and doesn't bounce.</summary>
    void MoveTo(Size size)
    {
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
    static void Fade(UIElement element, bool show)
    {
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
