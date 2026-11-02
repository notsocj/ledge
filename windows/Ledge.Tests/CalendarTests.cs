namespace Ledge.Tests;

public class CalendarTests
{
    // A daily standup in New York time that started a year ago, a one-off with a Teams link, an all-day
    // event, and a cancelled meeting.
    const string Ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Ledge//Test//EN
        BEGIN:VTIMEZONE
        TZID:America/New_York
        BEGIN:STANDARD
        DTSTART:19701101T020000
        RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU
        TZOFFSETFROM:-0400
        TZOFFSETTO:-0500
        END:STANDARD
        BEGIN:DAYLIGHT
        DTSTART:19700308T020000
        RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU
        TZOFFSETFROM:-0500
        TZOFFSETTO:-0400
        END:DAYLIGHT
        END:VTIMEZONE
        BEGIN:VEVENT
        UID:standup
        SUMMARY:Standup
        DTSTART;TZID=America/New_York:20251103T093000
        DTEND;TZID=America/New_York:20251103T094500
        RRULE:FREQ=DAILY
        LOCATION:https://meet.google.com/abc-defg-hij
        END:VEVENT
        BEGIN:VEVENT
        UID:review
        SUMMARY:Design review
        DTSTART:20261104T150000Z
        DTEND:20261104T160000Z
        DESCRIPTION:Join: https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0?context=1 thanks
        END:VEVENT
        BEGIN:VEVENT
        UID:holiday
        SUMMARY:Day off
        DTSTART;VALUE=DATE:20261104
        DTEND;VALUE=DATE:20261105
        END:VEVENT
        BEGIN:VEVENT
        UID:cancelled
        SUMMARY:Old sync
        STATUS:CANCELLED
        DTSTART:20261104T170000Z
        DTEND:20261104T173000Z
        END:VEVENT
        END:VCALENDAR
        """;

    static List<Meeting> Day() => CalendarFeed.Parse(Ics.Replace("\n", "\r\n"), new DateTime(2026, 11, 4, 0, 0, 0, DateTimeKind.Local), new DateTime(2026, 11, 5, 0, 0, 0, DateTimeKind.Local));

    [Fact]
    public void ExpandsRepeatsAndSkipsCancelled()
    {
        var titles = Day().Select(meeting => meeting.Title).ToList();
        Assert.Contains("Standup", titles);
        Assert.Contains("Design review", titles);
        Assert.Contains("Day off", titles);
        Assert.DoesNotContain("Old sync", titles);
    }

    [Fact]
    public void ConvertsToLocalTimeAndFindsJoinLinks()
    {
        var review = Day().Single(meeting => meeting.Title == "Design review");
        Assert.Equal(new DateTime(2026, 11, 4, 15, 0, 0, DateTimeKind.Utc).ToLocalTime(), review.Start);
        Assert.StartsWith("https://teams.microsoft.com/l/meetup-join/", review.JoinLink);
        Assert.EndsWith("context=1", review.JoinLink);
        Assert.Equal("https://meet.google.com/abc-defg-hij", Day().First(meeting => meeting.Title == "Standup").JoinLink);
        Assert.True(Day().Single(meeting => meeting.Title == "Day off").AllDay);
    }

    [Theory]
    [InlineData("webcal://calendar.example.com/a.ics", "https://calendar.example.com/a.ics")]
    [InlineData("  https://outlook.office365.com/owa/calendar/x/calendar.ics \n", "https://outlook.office365.com/owa/calendar/x/calendar.ics")]
    [InlineData("hello there", null)]
    [InlineData("file:///C:/secret.ics", null)]
    [InlineData(null, null)]
    public void AcceptsOnlyWebCalendarLinks(string? pasted, string? link) => Assert.Equal(link, CalendarFeed.Normalize(pasted));

    [Fact]
    public void AlertsOnceInTheTwoMinutesBefore()
    {
        var now = new DateTime(2026, 11, 4, 10, 0, 0);
        var meetings = new List<Meeting>
        {
            new("All day", now.Date, now.Date.AddDays(1), true, null),
            new("Later", now.AddMinutes(30), now.AddMinutes(60), false, null),
            new("Soon", now.AddMinutes(2), now.AddMinutes(30), false, null),
        };
        Assert.Equal("Soon", CalendarFeed.DueForAlert(meetings, now, new HashSet<string>())?.Title);
        Assert.Null(CalendarFeed.DueForAlert(meetings, now, new HashSet<string> { meetings[2].Key }));
        Assert.Null(CalendarFeed.DueForAlert(meetings, now.AddMinutes(-5), new HashSet<string>()));
    }
}
