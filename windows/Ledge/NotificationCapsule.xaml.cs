using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Media;

namespace Ledge;

/// <summary>Notification content inside the one island surface. It stays mounted through
/// dismissal and replacement; the island's morph controls when there is room to reveal it.</summary>
public partial class NotificationCapsule : UserControl
{
    readonly NotificationMotion motion = new();
    TimeSpan? lastFrame;
    bool rendering;
    public bool IsPresent => motion.IsVisible;
    public event Action? Dismissed;
    internal bool AnimateAutomatically { get; set; } = true;
    double reveal = 1;
    internal double Reveal
    {
        get => reveal;
        set { reveal = Math.Clamp(value, 0, 1); Presentation.Opacity = motion.Opacity * reveal; }
    }

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

    /// <summary>Full-screen apps and shutdown clear the content without leaving a pending fade.</summary>
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
        if (!motion.IsFading) StopRendering();
    }

    void StartRendering()
    {
        if (rendering || !AnimateAutomatically || !IsLoaded || !motion.IsFading) return;
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
        Presentation.Opacity = motion.Opacity * reveal;
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
