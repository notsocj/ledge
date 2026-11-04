using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Media;

namespace Ledge;

/// <summary>The Windows counterpart of the Mac's liquid capsule. It stays mounted through
/// dismissal and replacement, with one rendering subscription only while values are moving.</summary>
public partial class NotificationCapsule : UserControl
{
    readonly NotificationMotion motion = new();
    TimeSpan? lastFrame;
    bool rendering;
    public bool IsPresent => motion.IsVisible;
    public event Action? Dismissed;
    internal bool AnimateAutomatically { get; set; } = true;

    public NotificationCapsule()
    {
        InitializeComponent();
        Visibility = Visibility.Collapsed;
        Loaded += (_, _) => StartRendering();
        Unloaded += (_, _) => StopRendering();
        Apply();
    }

    public void Show(NotificationContent content, bool? reduceMotion = null)
    {
        TitleText.Text = content.Title;
        DetailText.Text = content.Detail;
        StatusText.Text = content.Status;
        StatusText.Visibility = content.Status.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        StatusText.Foreground = new SolidColorBrush(content.Tone switch
        {
            NotificationTone.Iris => Color.FromRgb(184, 166, 255),
            NotificationTone.Mint => Color.FromRgb(168, 219, 199),
            NotificationTone.Amber => Color.FromRgb(240, 204, 135),
            _ => Colors.White,
        });
        BadgeGlyph.Text = content.Glyph;
        BadgeGlyph.Visibility = content.Swatch is null ? Visibility.Visible : Visibility.Collapsed;
        BadgeSwatch.Fill = content.Swatch is { } color ? new SolidColorBrush(color) : null;
        BadgeSwatch.Visibility = content.Swatch is null ? Visibility.Collapsed : Visibility.Visible;
        AutomationProperties.SetName(this, content.AccessibilityLabel);
        motion.Show(reduceMotion ?? !SystemParameters.ClientAreaAnimation, content.Immediate);
        Visibility = Visibility.Visible;
        Apply();
        StartRendering();
        UIElementAutomationPeer.FromElement(this)?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
    }

    public void Dismiss(bool? reduceMotion = null)
    {
        motion.Dismiss(reduceMotion ?? !SystemParameters.ClientAreaAnimation);
        Apply();
        StartRendering();
    }

    /// <summary>Full-screen apps and shutdown remove the overlay without leaving a pending fade.</summary>
    internal void Clear()
    {
        StopRendering();
        motion.Dismiss(reduceMotion: true);
        motion.Step(1);
        Apply();
    }

    internal void Advance(double seconds)
    {
        motion.Step(seconds);
        Apply();
        if (!motion.IsMoving) StopRendering();
    }

    void StartRendering()
    {
        if (rendering || !AnimateAutomatically || !IsLoaded || !motion.IsMoving) return;
        rendering = true;
        lastFrame = null;
        CompositionTarget.Rendering += OnFrame;
    }

    void StopRendering()
    {
        if (!rendering) return;
        CompositionTarget.Rendering -= OnFrame;
        rendering = false;
        lastFrame = null;
    }

    void OnFrame(object? sender, EventArgs e)
    {
        var now = ((RenderingEventArgs)e).RenderingTime;
        if (now == lastFrame) return;
        var seconds = lastFrame is { } previous ? (now - previous).TotalSeconds : 1.0 / 60;
        lastFrame = now;
        Advance(seconds);
    }

    void Apply()
    {
        var tension = 1 - motion.SurfaceProgress;
        Travel.Y = -18 * tension;
        Stretch.ScaleX = 1 - 0.04 * tension;
        Stretch.ScaleY = 1 + 0.08 * tension;
        var bend = 8 * tension;
        var surface = new StreamGeometry();
        using (var path = surface.Open())
        {
            path.BeginFigure(new Point(32, 0), true, true);
            path.BezierTo(new Point(150, -bend * 0.3), new Point(214, -bend * 0.3), new Point(332, 0), true, false);
            path.ArcTo(new Point(332, 64), new Size(32, 32), 0, false, SweepDirection.Clockwise, true, false);
            path.BezierTo(new Point(214, 64 + bend), new Point(150, 64 + bend), new Point(32, 64), true, false);
            path.ArcTo(new Point(32, 0), new Size(32, 32), 0, false, SweepDirection.Clockwise, true, false);
        }
        surface.Transform = new TranslateTransform(24, 24);
        surface.Freeze();
        Shell.Data = Sheen.Data = surface;
        Sheen.Opacity = Math.Min(1, Math.Abs(tension) * 0.8);
        Presentation.Opacity = motion.Opacity;
        if (!motion.IsVisible)
        {
            var wasVisible = Visibility == Visibility.Visible;
            Visibility = Visibility.Collapsed;
            TitleText.Text = DetailText.Text = StatusText.Text = "";
            BadgeSwatch.Fill = null;
            AutomationProperties.SetName(this, "");
            if (wasVisible) Dismissed?.Invoke();
        }
    }
}
