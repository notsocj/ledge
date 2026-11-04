namespace Ledge;

public enum NotificationPriority { Ambient = 10, Normal = 20, Attention = 30 }

/// <summary>A small, in-memory scheduler for the one island. Visible time pauses while the island
/// is occupied, but an absolute freshness deadline prevents a backlog after meetings or sleep.</summary>
public sealed class NotificationQueue(Func<DateTimeOffset>? clock = null)
{
    const int Capacity = 4, RecentCapacity = 32;
    readonly Func<DateTimeOffset> now = clock ?? (() => DateTimeOffset.UtcNow);
    readonly List<Entry> pending = [];
    readonly Dictionary<string, Seen> recent = new(StringComparer.Ordinal);
    Entry? active;
    bool available = true;
    long sequence;

    public NotificationContent? Current => active?.Content;
    public long CurrentId => active?.Id ?? 0;
    public int PendingCount => pending.Count;

    /// <summary>The UI needs one deadline timer, not a continuous polling loop.</summary>
    public TimeSpan? TimeUntilNextChange
    {
        get
        {
            var deadlines = pending.Select(entry => entry.ExpiresAt).ToList();
            if (active is { } current)
                deadlines.Add(current.VisibleUntil < current.ExpiresAt ? current.VisibleUntil : current.ExpiresAt);
            if (deadlines.Count == 0) return null;
            var wait = deadlines.Min() - now();
            return wait > TimeSpan.Zero ? wait : TimeSpan.Zero;
        }
    }

    public void Enqueue(NotificationContent content, double seconds = 2.5)
    {
        var time = now();
        Advance(time);
        if (!double.IsFinite(seconds) || seconds <= 0) return;
        var duration = TimeSpan.FromSeconds(Math.Min(seconds, 300));
        var freshness = TimeSpan.FromSeconds(Math.Max(duration.TotalSeconds, content.FreshSeconds));
        var expires = time + freshness;
        if (content.ExpiresAt is { } limit && limit < expires) expires = limit;
        if (expires <= time) return;
        var key = content.GroupKey.Length == 0 ? $"message:{content.Title}" : content.GroupKey;

        // Keyboard/direct feedback is never replayed later and remains responsive to repetitions.
        if (content.Immediate)
        {
            if (!available) return;
            SuspendCurrent(time);
            active = new Entry(++sequence, content, key, time, expires, duration) { VisibleUntil = time + duration };
            Trim();
            return;
        }

        // Remember the original expiry, even after an alert finishes: repeated identical hooks
        // cannot keep it visible forever or continuously restart its jelly animation.
        if (recent.TryGetValue(key, out var seen) && seen.Content == content && seen.ExpiresAt > time) return;
        recent[key] = new Seen(content, expires, ++sequence);
        if (recent.Count > RecentCapacity)
            recent.Remove(recent.MinBy(pair => pair.Value.Order).Key);

        // A newer state from the same source resolves its older state (e.g. Needs you → Done).
        pending.RemoveAll(entry => entry.Key == key);
        if (active?.Key == key) active = null;
        pending.Add(new Entry(sequence, content, key, time, expires, duration));
        Promote(time);
        Trim();
    }

    public void SetAvailable(bool canPresent)
    {
        var time = now();
        Advance(time, promote: false);
        available = canPresent;
        if (!available) SuspendCurrent(time);
        else Promote(time);
        Trim();
    }

    public void Tick() => Advance(now());

    /// <summary>Disabling a tool also removes its deferred alerts and duplicate history.</summary>
    public void RemoveWhere(Predicate<NotificationContent> predicate)
    {
        var time = now();
        Advance(time, promote: false);
        if (active is { } current && predicate(current.Content)) active = null;
        pending.RemoveAll(entry => predicate(entry.Content));
        foreach (var key in recent.Where(pair => predicate(pair.Value.Content)).Select(pair => pair.Key).ToArray()) recent.Remove(key);
        Promote(time);
    }

    public void Clear()
    {
        active = null;
        pending.Clear();
        recent.Clear();
    }

    void Advance(DateTimeOffset time, bool promote = true)
    {
        if (active is { } current && (current.ExpiresAt <= time || current.VisibleUntil <= time)) active = null;
        pending.RemoveAll(entry => entry.ExpiresAt <= time || entry.Remaining <= TimeSpan.Zero);
        foreach (var key in recent.Where(pair => pair.Value.ExpiresAt <= time).Select(pair => pair.Key).ToArray()) recent.Remove(key);
        if (promote) Promote(time);
    }

    void Promote(DateTimeOffset time)
    {
        if (!available || pending.Count == 0) return;
        var next = pending.OrderByDescending(entry => entry.Content.Priority).ThenBy(entry => entry.Id).First();
        if (active is { } current && (current.Content.Immediate || current.Content.Priority >= next.Content.Priority)) return;
        pending.Remove(next);
        SuspendCurrent(time);
        active = next;
        active.VisibleUntil = time + active.Remaining;
    }

    void SuspendCurrent(DateTimeOffset time)
    {
        if (active is not { } current) return;
        active = null;
        // Immediate feedback disappears when interrupted. Other alerts retain only unread time.
        if (current.Content.Immediate || current.ExpiresAt <= time) return;
        current.Remaining = current.VisibleUntil - time;
        if (current.Remaining > TimeSpan.Zero) pending.Add(current);
    }

    void Trim()
    {
        while (pending.Count > Capacity)
        {
            var oldestLowPriority = pending.OrderBy(entry => entry.Content.Priority).ThenBy(entry => entry.Id).First();
            pending.Remove(oldestLowPriority);
        }
    }

    sealed class Entry(long id, NotificationContent content, string key, DateTimeOffset createdAt,
                       DateTimeOffset expiresAt, TimeSpan remaining)
    {
        public long Id { get; } = id;
        public NotificationContent Content { get; } = content;
        public string Key { get; } = key;
        public DateTimeOffset ExpiresAt { get; } = expiresAt;
        public TimeSpan Remaining { get; set; } = remaining;
        public DateTimeOffset VisibleUntil { get; set; } = createdAt + remaining;
    }

    sealed record Seen(NotificationContent Content, DateTimeOffset ExpiresAt, long Order);
}
