using System.Windows;

namespace Ledge;

/// <summary>
/// Decides when the island opens and closes from pointer samples, with the Mac's rules: it opens on
/// intent (a push against the top edge, or a brief rest over the island) so a pointer sweeping past
/// doesn't set it off, and it closes at once when the pointer leaves decisively, or after a moment's
/// grace when it only slips past the edge. Everything is in screen pixels.
/// </summary>
public sealed class HoverIntent
{
    public enum Decision { None, Open, Close }

    /// <summary>Screen pixels per device-independent pixel on the island's monitor.</summary>
    public double Scale { get; set; } = 1;

    Point? lastPoint;
    double lastTime, speed;
    double? restingSince, slippedAt;

    public Decision Update(Point pointer, double seconds, Rect island, double screenTop, bool expanded)
    {
        Track(pointer, seconds);
        return expanded ? WhileOpen(pointer, seconds, island) : WhileClosed(pointer, seconds, island, screenTop);
    }

    /// <summary>Forgets timers in flight, for when the island opens or closes for another reason.</summary>
    public void Reset() => restingSince = slippedAt = null;

    Decision WhileClosed(Point pointer, double seconds, Rect island, double screenTop)
    {
        slippedAt = null;
        // The island widened a little, and stretched up to the screen's top edge where the pointer rests.
        var hot = new Rect(island.Left - 14 * Scale, screenTop, island.Width + 28 * Scale, island.Bottom - screenTop);
        if (!hot.Contains(pointer))
        {
            restingSince = null;
            return Decision.None;
        }
        if (pointer.Y <= screenTop + 1 && speed < 2400 * Scale) return Open();
        restingSince ??= seconds;
        return seconds - restingSince >= 0.055 && speed < 650 * Scale ? Open() : Decision.None;
    }

    Decision WhileOpen(Point pointer, double seconds, Rect island)
    {
        restingSince = null;
        if (Inflate(island, 14).Contains(pointer))
        {
            slippedAt = null;
            return Decision.None;
        }
        if (!Inflate(island, 90).Contains(pointer)) return Close();
        slippedAt ??= seconds;
        return seconds - slippedAt >= 0.17 ? Close() : Decision.None;
    }

    Decision Open()
    {
        Reset();
        return Decision.Open;
    }

    Decision Close()
    {
        Reset();
        return Decision.Close;
    }

    void Track(Point pointer, double seconds)
    {
        if (lastPoint is { } last && seconds > lastTime)
        {
            var instant = (pointer - last).Length / (seconds - lastTime);
            speed = speed * 0.6 + instant * 0.4;
        }
        lastPoint = pointer;
        lastTime = seconds;
    }

    Rect Inflate(Rect rect, double by)
    {
        rect.Inflate(by * Scale, by * Scale);
        return rect;
    }
}
