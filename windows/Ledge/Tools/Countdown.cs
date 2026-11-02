namespace Ledge;

/// <summary>One countdown at a time, ticking in the closed island while it runs.</summary>
public sealed class Countdown(Func<DateTime> now)
{
    DateTime? endsAt;
    TimeSpan? pausedRemaining;

    public TimeSpan Total { get; private set; }
    public bool IsRunning => endsAt is not null;
    public bool IsActive => endsAt is not null || pausedRemaining is not null;

    public TimeSpan Remaining => endsAt is { } end
        ? (end > now() ? end - now() : TimeSpan.Zero)
        : pausedRemaining ?? TimeSpan.Zero;

    public void Start(double minutes)
    {
        Total = TimeSpan.FromMinutes(minutes);
        endsAt = now() + Total;
        pausedRemaining = null;
    }

    public void Pause()
    {
        if (endsAt is null) return;
        pausedRemaining = Remaining;
        endsAt = null;
    }

    public void Resume()
    {
        if (pausedRemaining is not { } left) return;
        endsAt = now() + left;
        pausedRemaining = null;
    }

    public void AddMinute()
    {
        Total += TimeSpan.FromMinutes(1);
        if (endsAt is { } end) endsAt = end.AddMinutes(1);
        else if (pausedRemaining is { } left) pausedRemaining = left + TimeSpan.FromMinutes(1);
    }

    public void Cancel() => (endsAt, pausedRemaining) = (null, null);

    /// <summary>Call regularly while running. Returns true once, when the countdown reaches zero.</summary>
    public bool Tick()
    {
        if (endsAt is not { } end || now() < end) return false;
        endsAt = null;
        return true;
    }

    /// <summary>"25:00", "4:05", "1:02:03". Rounds up, so a fresh 25 minute timer reads 25:00, not 24:59.</summary>
    public static string Format(TimeSpan time)
    {
        var seconds = (int)Math.Ceiling(time.TotalSeconds);
        return seconds >= 3600 ? $"{seconds / 3600}:{seconds / 60 % 60:00}:{seconds % 60:00}" : $"{seconds / 60}:{seconds % 60:00}";
    }
}
