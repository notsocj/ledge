namespace Ledge;

/// <summary>A single retained presentation: a new alert retargets the current spring and fade,
/// including during dismissal. No delayed completion can remove its replacement.</summary>
public sealed class NotificationMotion
{
    // Use the island's existing spring and a 1000-unit range to retain its subpixel settling precision.
    readonly Spring progress = new(0);
    double fadeStart, fadeElapsed, fadeDuration;
    bool moves = true, immediate;

    public double Progress => progress.Value / 1000;
    public double SurfaceProgress => moves ? Progress : 1;
    public double Opacity { get; private set; }
    public bool IsPresented { get; private set; }
    public bool IsVisible => IsPresented || Opacity > 0;
    public bool IsFading => fadeElapsed < fadeDuration;
    public bool IsMoving => !progress.IsSettled || fadeElapsed < fadeDuration;

    public void Show(bool reduceMotion = false, bool immediate = false)
    {
        this.immediate = immediate;
        moves = !reduceMotion && !immediate;
        IsPresented = true;
        if (moves) progress.Retarget(1000, 0.5, 0.2);
        else progress.Snap(1000);
        FadeTo(1, immediate ? 0 : 0.15);
    }

    public void Dismiss(bool reduceMotion = false)
    {
        IsPresented = false;
        moves = moves && !reduceMotion;
        if (moves) progress.Retarget(0, 0.3, 0);
        else progress.Snap(0);
        FadeTo(0, immediate ? 0 : reduceMotion ? 0.15 : 0.22);
    }

    void FadeTo(double target, double duration)
    {
        fadeStart = Opacity;
        fadeElapsed = 0;
        fadeDuration = Opacity == target ? 0 : duration;
        if (fadeDuration == 0) Opacity = target;
        if (!IsVisible) progress.Snap(0);
    }

    public bool Step(double seconds)
    {
        if (!double.IsFinite(seconds) || seconds <= 0) return IsMoving;
        progress.Step(seconds);
        if (fadeElapsed < fadeDuration)
        {
            fadeElapsed = Math.Min(fadeDuration, fadeElapsed + seconds);
            var eased = 1 - Math.Pow(1 - fadeElapsed / fadeDuration, 5);
            Opacity = fadeStart + ((IsPresented ? 1 : 0) - fadeStart) * eased;
        }
        if (!IsVisible) progress.Snap(0);
        return IsMoving;
    }
}
