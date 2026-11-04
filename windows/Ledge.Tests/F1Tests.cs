using System.IO;
using System.Net.Http;
using System.Text.Json;

namespace Ledge.Tests;

public class F1Tests
{
    static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-11-05T10:00:00Z");
    const string Empty = "{\"MRData\":{\"RaceTable\":{\"Races\":[]}}}";
    static string Response(string race) => "{\"MRData\":{\"RaceTable\":{\"Races\":[" + race + "]}}}";
    static string Race(int year = 2026, int round = 20, string date = "2026-11-08", string time = ",\"time\":\"17:00:00Z\"", string extra = "") =>
        $$"""{"season":"{{year}}","round":"{{round}}","raceName":"São Paulo Grand Prix","Circuit":{"circuitName":"Interlagos"},"date":"{{date}}"{{time}}{{extra}}} """;
    static string Results(int count = 3) => ",\"Results\":[" + string.Join(',', Enumerable.Range(1, count)
        .Reverse().Select(position => $$$"""{"position":"{{{position}}}","Driver":{"givenName":"Driver","familyName":"{{{position}}}"},"Constructor":{"name":"Team {{{position}}}"}}""")) + "]";

    [Fact]
    public void OptInIsOffForEveryPersonaAndLegacySettings()
    {
        foreach (var persona in Enum.GetValues<Persona>()) Assert.False(new Settings { Personas = [persona] }.IsOn(Tool.F1));
        Assert.False(new Settings().IsOn(Tool.F1));
        var settings = JsonSerializer.Deserialize<Settings>("{\"SetupDone\":true}")!;
        Assert.False(settings.F1Enabled);
        settings.F1Enabled = true;
        settings.Personas = [Persona.Student];
        Assert.True(settings.IsOn(Tool.F1));
        Assert.True(JsonSerializer.Deserialize<Settings>(JsonSerializer.Serialize(settings))!.F1Enabled);
    }

    [Fact]
    public void MissingTimeStaysUnknownAndSprintAliasesDoNotDuplicate()
    {
        var race = Assert.Single(F1Schedule.ParseRaces(Response(Race(time: "", extra:
            ",\"SprintQualifying\":{\"date\":\"2026-11-06\",\"time\":\"18:00:00Z\"},\"SprintShootout\":{\"date\":\"2026-11-06\",\"time\":\"18:00:00Z\"}"))));
        Assert.Null(race.Start);
        Assert.Equal("Time TBC", F1Schedule.Countdown(race, Now));
        Assert.Equal(2, race.Sessions.Count);
        Assert.Equal("Sprint qualifying", race.Sessions[0].Name);
        Assert.Contains("Time TBC", race.Sessions[1].LocalTime);
    }

    [Fact]
    public void PodiumRequiresAllThreePositionsAndSortsThem()
    {
        Assert.Null(F1Schedule.ParsePodium(Response(Race(extra: Results(2)))));
        var podium = F1Schedule.ParsePodium(Response(Race(extra: Results())))!;
        Assert.Equal(new[] { 1, 2, 3 }, podium.Drivers.Select(driver => driver.Position));
        Assert.Equal("Driver 1", podium.Drivers[0].Name);
    }

    [Fact]
    public void PendingIsNotLiveAndDoesNotTrapTheNextRace()
    {
        var recent = new F1Race(2026, 20, "Recent", "Circuit", new DateOnly(2026, 11, 5), Now.AddHours(-2), []);
        var next = recent with { Round = 21, Name = "Next", Date = new DateOnly(2026, 11, 12), Start = Now.AddDays(7) };
        var data = new F1Data([recent, next], null, Now);
        Assert.Equal(recent, F1Schedule.Focus(data, Now));
        Assert.Equal("Results pending", F1Schedule.Countdown(recent, Now));
        Assert.Equal(next, F1Schedule.Focus(data, Now.AddHours(24)));
        Assert.Equal(next, F1Schedule.Focus(data with { Podium = new(recent, []) }, Now));
    }

    [Fact]
    public void CountdownDoesNotRoundAStartingRaceDownToZero()
    {
        var race = Assert.Single(F1Schedule.ParseRaces(Response(Race())));
        Assert.Equal("3d 7h", F1Schedule.Countdown(race, Now));
        Assert.Equal("1m", F1Schedule.Countdown(race, race.Start!.Value.AddSeconds(-1)));
    }

    [Fact]
    public async Task PollingIsOptInThrottledAndUsesPublishedWinnerRound()
    {
        var path = TemporaryPath();
        var calls = new List<string>();
        var now = Now;
        var feed = new F1Feed(path, (endpoint, _) =>
        {
            calls.Add(endpoint);
            return Task.FromResult(endpoint.Contains("results/1") ? Response(Race(round: 19, date: "2026-11-01"))
                : endpoint.Contains("/19/results") ? Response(Race(round: 19, date: "2026-11-01", extra: Results()))
                : Response(Race()));
        }, () => now);
        try
        {
            await feed.RefreshAsync();
            Assert.Empty(calls);
            feed.SetEnabled(true);
            Assert.Equal(3, calls.Count);
            Assert.Equal(19, feed.Data?.Podium?.Race.Round);
            await feed.RefreshAsync();
            Assert.Equal(3, calls.Count);
            now = now.AddMinutes(31);
            await feed.RefreshAsync();
            Assert.Equal(6, calls.Count);
            feed.SetEnabled(false);
            now = now.AddHours(1);
            await feed.RefreshAsync();
            Assert.Equal(6, calls.Count);
        }
        finally { feed.SetEnabled(false); Directory.Delete(Path.GetDirectoryName(path)!, true); }
    }

    [Fact]
    public void OffSeasonReadsNextCalendarAndPreviousPublishedPodium()
    {
        var path = TemporaryPath();
        var calls = new List<string>();
        var feed = new F1Feed(path, (endpoint, _) =>
        {
            calls.Add(endpoint);
            return Task.FromResult(endpoint.StartsWith("2027.json") ? Response(Race(2027, 1, "2027-03-07"))
                : endpoint == "2025/results/1.json?limit=100" ? Response(Race(2025, 24, "2025-12-07"))
                : endpoint == "2025/24/results.json?limit=3" ? Response(Race(2025, 24, "2025-12-07", extra: Results())) : Empty);
        }, () => Now);
        try
        {
            feed.SetEnabled(true);
            Assert.Contains("2027.json?limit=100", calls);
            Assert.Equal(2027, F1Schedule.Focus(feed.Data, Now)?.Season);
            Assert.Equal(2025, feed.Data?.Podium?.Race.Season);
        }
        finally { feed.SetEnabled(false); Directory.Delete(Path.GetDirectoryName(path)!, true); }
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("{\"Races\":null}")]
    [InlineData("{\"Races\":[null]}")]
    [InlineData("{\"Races\":[],\"Podium\":{\"Race\":null,\"Drivers\":null}}")]
    [InlineData("{not json")]
    public void InvalidCacheDoesNotPreventEnable(string cache)
    {
        var path = TemporaryPath();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, cache);
        var feed = new F1Feed(path, (_, _) => Task.FromException<string>(new HttpRequestException()), () => Now);
        try
        {
            feed.SetEnabled(true);
            Assert.True(feed.Enabled);
            Assert.Null(feed.Data);
            Assert.NotNull(feed.Problem);
        }
        finally { feed.SetEnabled(false); Directory.Delete(Path.GetDirectoryName(path)!, true); }
    }

    [Fact]
    public async Task DisableCancelsWorkAndReenableCanTryAgain()
    {
        var path = TemporaryPath();
        var canceled = false;
        var calls = 0;
        var feed = new F1Feed(path, async (_, token) =>
        {
            calls++;
            try { await Task.Delay(Timeout.Infinite, token); }
            catch (OperationCanceledException) { canceled = true; throw; }
            return Empty;
        }, () => Now);
        feed.SetEnabled(true);
        feed.SetEnabled(false);
        for (var attempt = 0; attempt < 100 && !canceled; attempt++) await Task.Delay(10);
        Assert.True(canceled);
        Assert.Null(feed.Data);
        feed.SetEnabled(true);
        for (var attempt = 0; attempt < 100 && calls < 2; attempt++) await Task.Delay(10);
        Assert.Equal(2, calls);
        feed.SetEnabled(false);
    }

    [Fact]
    public void OfflineCacheRetainsTimestampAndContent()
    {
        var path = TemporaryPath();
        var saved = new F1Data(F1Schedule.ParseRaces(Response(Race())), null, Now.AddHours(-2));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(saved));
        var feed = new F1Feed(path, (_, _) => Task.FromException<string>(new HttpRequestException()), () => Now);
        try
        {
            feed.SetEnabled(true);
            Assert.Equal(saved.UpdatedAt, feed.Data?.UpdatedAt);
            Assert.Equal(saved.Races[0].Name, feed.Data?.Races[0].Name);
            Assert.NotNull(feed.Problem);
        }
        finally { feed.SetEnabled(false); Directory.Delete(Path.GetDirectoryName(path)!, true); }
    }

    static string TemporaryPath() => Path.Combine(Path.GetTempPath(), $"ledge-f1-{Guid.NewGuid()}", "cache.json");
}
