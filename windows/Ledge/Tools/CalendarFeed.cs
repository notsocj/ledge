using System.Net.Http;
using System.Text.RegularExpressions;
using Ical.Net.CalendarComponents;
using IcalCalendar = Ical.Net.Calendar;

namespace Ledge;

public sealed record Meeting(string Title, DateTime Start, DateTime End, bool AllDay, string? JoinLink)
{
    /// <summary>Identifies one occurrence, so a repeating meeting is announced each time it comes round.</summary>
    public string Key => $"{Title}|{Start:O}";
}

/// <summary>Your calendar, read from its private ICS link (Outlook and Google Calendar both offer one),
/// fetched every 15 minutes. Windows has no calendar API like the Mac's, so this is the way in.</summary>
public sealed partial class CalendarFeed
{
    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };

    public IReadOnlyList<Meeting> Meetings { get; private set; } = [];
    /// <summary>Set when the last fetch failed, in words for the person, not the error.</summary>
    public string? Problem { get; private set; }
    public event Action? Changed;

    public async Task RefreshAsync(string? link)
    {
        if (link is null)
        {
            (Meetings, Problem) = ([], null);
            Changed?.Invoke();
            return;
        }
        try
        {
            var ics = await Http.GetStringAsync(link);
            var today = DateTime.Today;
            Meetings = await Task.Run(() => Parse(ics, today, today.AddDays(2)));
            Problem = null;
        }
        catch (Exception)
        {
            // Keep the last good meetings; a laptop offline for a while shouldn't lose its day.
            Problem = "Couldn't reach your calendar. Ledge keeps trying every 15 minutes.";
        }
        Changed?.Invoke();
    }

    /// <summary>A calendar link from whatever was pasted: webcal:// becomes https://, anything else that
    /// isn't a web address is turned away.</summary>
    public static string? Normalize(string? text)
    {
        var trimmed = text?.Trim() ?? "";
        if (trimmed.StartsWith("webcal://", StringComparison.OrdinalIgnoreCase)) trimmed = "https://" + trimmed[9..];
        return Uri.TryCreate(trimmed, UriKind.Absolute, out var uri) && uri.Scheme is "https" or "http" ? uri.AbsoluteUri : null;
    }

    /// <summary>Every occurrence between two local times, repeating meetings expanded, cancelled ones left out, earliest first.</summary>
    public static List<Meeting> Parse(string ics, DateTime from, DateTime to)
    {
        var calendar = IcalCalendar.Load(ics);
        var meetings = new List<Meeting>();
        foreach (var occurrence in calendar.GetOccurrences(from, to))
        {
            if (occurrence.Source is not CalendarEvent item || string.Equals(item.Status, "CANCELLED", StringComparison.OrdinalIgnoreCase)) continue;
            var start = occurrence.Period.StartTime.AsSystemLocal;
            var end = occurrence.Period.EndTime?.AsSystemLocal ?? start + item.Duration;
            if (end <= from || start >= to) continue;
            meetings.Add(new(item.Summary ?? "Untitled", start, end, item.IsAllDay, JoinLink(item.Location, item.Url?.ToString(), item.Description)));
        }
        return [.. meetings.OrderBy(meeting => meeting.Start).ThenBy(meeting => meeting.Title)];
    }

    /// <summary>The first video-call link in a meeting's location, link or notes.</summary>
    public static string? JoinLink(params string?[] texts) =>
        texts.Select(text => text is null ? null : MeetingLink().Match(text)).FirstOrDefault(match => match?.Success == true)?.Value;

    [GeneratedRegex(@"https://([\w-]+\.)*(teams\.microsoft\.com|teams\.live\.com|zoom\.us|meet\.google\.com|webex\.com|whereby\.com|gotomeeting\.com)/[^\s""<>]+", RegexOptions.IgnoreCase)]
    private static partial Regex MeetingLink();

    /// <summary>The next timed meeting starting within two minutes that hasn't been announced yet.</summary>
    public static Meeting? DueForAlert(IEnumerable<Meeting> meetings, DateTime now, IReadOnlySet<string> announced) =>
        meetings.FirstOrDefault(meeting => !meeting.AllDay && meeting.Start > now && meeting.Start - now <= TimeSpan.FromMinutes(2) && !announced.Contains(meeting.Key));
}
