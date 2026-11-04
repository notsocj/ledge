using System.Windows;

namespace Ledge;

/// <summary>The single island's dimensions and liquid edge. Notifications retarget this same
/// surface, including when replaced or interrupted by opening the full panel.</summary>
public sealed class IslandMotion(Size initialSize)
{
    readonly Spring width = new(initialSize.Width), height = new(initialSize.Height), notification = new(0);

    public double Width => Math.Max(0, width.Value);
    public double Height => Math.Max(0, height.Value);
    public double NotificationProgress => notification.Value / 1000;
    public double CornerRadius => Math.Min(Height / 2, 28 + 4 * Math.Clamp(NotificationProgress, 0, 1));
    public double Bend
    {
        get
        {
            var phase = Math.Clamp(NotificationProgress, -0.08, 1.08);
            return 32 * phase * (1 - phase);
        }
    }
    // Reveal only after the narrow resting island has made room. Text and icons never scale.
    public double NotificationReveal => Math.Clamp((Width - 240) / 124, 0, 1) * Math.Clamp((Height - 40) / 24, 0, 1);
    public bool IsMoving => !width.IsSettled || !height.IsSettled || !notification.IsSettled;

    public void Retarget(Size target, bool notification = false, bool reduceMotion = false, bool immediate = false)
    {
        var phase = notification ? 1000 : 0;
        if (reduceMotion || immediate)
        {
            width.Snap(target.Width);
            height.Snap(target.Height);
            this.notification.Snap(phase);
            return;
        }
        var growing = target.Width > width.Target || target.Height > height.Target;
        var (duration, bounce) = growing ? (0.5, 0.2) : (0.3, 0.0);
        if (target.Width != width.Target) width.Retarget(target.Width, duration, bounce);
        if (target.Height != height.Target) height.Retarget(target.Height, duration, bounce);
        if (phase != this.notification.Target) this.notification.Retarget(phase, duration, bounce);
    }

    public bool Step(double seconds)
    {
        if (!double.IsFinite(seconds) || seconds <= 0) return IsMoving;
        return width.Step(seconds) | height.Step(seconds) | notification.Step(seconds);
    }
}
