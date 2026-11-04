using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text.Json;

namespace Ledge;

public sealed record F1Session(string Name, DateOnly Date, DateTimeOffset? Start)
{
    public string LocalTime => Start is { } start ? start.ToLocalTime().ToString("ddd d MMM · HH:mm", CultureInfo.CurrentCulture)
        : $"{Date:ddd d MMM} · Time TBC";
}

public sealed record F1Driver(int Position, string Name, string Team);
public sealed record F1Race(int Season, int Round, string Name, string Circuit, DateOnly Date,
    DateTimeOffset? Start, IReadOnlyList<F1Session> Sessions)
{
    public string Key => $"{Season}/{Round}";
}
public sealed record F1Podium(F1Race Race, IReadOnlyList<F1Driver> Drivers);
public sealed record F1Data(IReadOnlyList<F1Race> Races, F1Podium? Podium, DateTimeOffset UpdatedAt);

/// <summary>Post-race and schedule data only. Scheduled starts never imply a race is live.</summary>
public static class F1Schedule
{
    public static F1Race? Pending(F1Data? data, DateTimeOffset now) => data?.Races
        .Where(race => race.Start is { } start && start <= now && now - start < TimeSpan.FromHours(24)
            && (data.Podium is null || race.Season > data.Podium.Race.Season
                || race.Season == data.Podium.Race.Season && race.Round > data.Podium.Race.Round))
        .MaxBy(race => race.Start);

    public static F1Race? Next(IEnumerable<F1Race> races, DateTimeOffset now) => races
        .Where(race => race.Start is { } start ? start > now : race.Date >= DateOnly.FromDateTime(now.UtcDateTime))
        .OrderBy(race => race.Date).ThenBy(race => race.Start).FirstOrDefault();

    public static F1Race? Focus(F1Data? data, DateTimeOffset now) => Pending(data, now) ?? (data is null ? null : Next(data.Races, now));

    public static string Countdown(F1Race? race, DateTimeOffset now)
    {
        if (race is null) return "Schedule pending";
        if (race.Start is not { } start) return "Time TBC";
        if (start <= now) return "Results pending";
        var minutes = Math.Max(1, (int)Math.Ceiling((start - now).TotalMinutes));
        if (minutes >= 1440) return $"{minutes / 1440}d {minutes % 1440 / 60}h";
        if (minutes >= 60) return $"{minutes / 60}h {minutes % 60}m";
        return $"{minutes}m";
    }

    public static IReadOnlyList<F1Race> ParseRaces(string json)
    {
        using var document = JsonDocument.Parse(json);
        var array = document.RootElement.GetProperty("MRData").GetProperty("RaceTable").GetProperty("Races");
        return [.. array.EnumerateArray().Select(ParseRace).OfType<F1Race>().OrderBy(race => race.Date)];
    }

    public static F1Podium? ParsePodium(string json)
    {
        using var document = JsonDocument.Parse(json);
        var races = document.RootElement.GetProperty("MRData").GetProperty("RaceTable").GetProperty("Races");
        foreach (var item in races.EnumerateArray().Reverse())
        {
            if (ParseRace(item) is not { } race || !item.TryGetProperty("Results", out var results)) continue;
            var drivers = new List<F1Driver>();
            foreach (var result in results.EnumerateArray())
            {
                if (!int.TryParse(Text(result, "position"), out var position) || position is < 1 or > 3
                    || !result.TryGetProperty("Driver", out var driver)) continue;
                var name = $"{Text(driver, "givenName")} {Text(driver, "familyName")}".Trim();
                if (name.Length == 0) continue;
                drivers.Add(new(position, name, result.TryGetProperty("Constructor", out var team) ? Text(team, "name") : ""));
            }
            if (drivers.Count == 3 && drivers.Select(driver => driver.Position).Distinct().Count() == 3)
                return new(race, [.. drivers.OrderBy(driver => driver.Position)]);
        }
        return null;
    }

    static F1Race? ParseRace(JsonElement race)
    {
        if (!int.TryParse(Text(race, "season"), out var season) || !int.TryParse(Text(race, "round"), out var round)
            || !DateOnly.TryParseExact(Text(race, "date"), "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date)) return null;
        var sessions = new List<F1Session>();
        foreach (var (key, name) in new[] { ("FirstPractice", "Practice 1"), ("SecondPractice", "Practice 2"), ("ThirdPractice", "Practice 3"),
                     ("SprintQualifying", "Sprint qualifying"), ("SprintShootout", "Sprint qualifying"), ("Sprint", "Sprint"), ("Qualifying", "Qualifying") })
        {
            if (race.TryGetProperty(key, out var session)
                && DateOnly.TryParseExact(Text(session, "date"), "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var day)
                && !sessions.Any(existing => existing.Name == name)) sessions.Add(new(name, day, Start(session)));
        }
        var start = Start(race);
        sessions.Add(new("Race", date, start));
        return new(season, round, Text(race, "raceName"), race.TryGetProperty("Circuit", out var circuit) ? Text(circuit, "circuitName") : "",
            date, start, [.. sessions.OrderBy(session => session.Date).ThenBy(session => session.Start)]);
    }

    static DateTimeOffset? Start(JsonElement item) => Text(item, "time") is { Length: > 0 } time
        && DateTimeOffset.TryParse($"{Text(item, "date")}T{time}", CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var start) ? start : null;

    static string Text(JsonElement item, string key) => item.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : "";
}

/// <summary>Opt-in polling. Public Jolpica data stays cached locally; disabling cancels in-flight work.</summary>
public sealed class F1Feed
{
    static readonly HttpClient Http = CreateClient();
    readonly string cachePath;
    readonly Func<string, CancellationToken, Task<string>> fetch;
    readonly Func<DateTimeOffset> now;
    CancellationTokenSource? lifetime;
    DateTimeOffset nextRefresh;
    bool refreshing;
    public F1Data? Data { get; private set; }
    public bool Enabled => lifetime is not null;
    public bool Updating { get; private set; }
    public string? Problem { get; private set; }
    public event Action? Changed;

    public F1Feed(string? cachePath = null, Func<string, CancellationToken, Task<string>>? fetch = null, Func<DateTimeOffset>? now = null)
    {
        this.cachePath = cachePath ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Ledge", "f1-cache.json");
        this.fetch = fetch ?? Fetch;
        this.now = now ?? (() => DateTimeOffset.UtcNow);
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled == Enabled) return;
        if (!enabled)
        {
            lifetime?.Cancel();
            lifetime?.Dispose();
            lifetime = null;
            Updating = false;
            Changed?.Invoke();
            return;
        }
        lifetime = new();
        if (Data is null)
        {
            try
            {
                var cached = JsonSerializer.Deserialize<F1Data>(File.ReadAllText(cachePath));
                if (ValidCache(cached)) Data = cached;
            }
            catch (Exception) { /* A missing or damaged cache should never prevent startup. */ }
        }
        nextRefresh = Data is { } saved && now() - saved.UpdatedAt < TimeSpan.FromMinutes(30) && saved.UpdatedAt <= now()
            ? saved.UpdatedAt.AddMinutes(F1Schedule.Pending(saved, now()) is null ? 30 : 5) : DateTimeOffset.MinValue;
        Changed?.Invoke();
        _ = RefreshAsync();
    }

    public async Task RefreshAsync()
    {
        if (Problem is null && Data is { } data && F1Schedule.Pending(data, now()) is not null
            && nextRefresh > data.UpdatedAt.AddMinutes(5)) nextRefresh = data.UpdatedAt.AddMinutes(5);
        if (lifetime is not { } source || refreshing || now() < nextRefresh) return;
        refreshing = Updating = true;
        Changed?.Invoke();
        var cancellation = source.Token;
        try
        {
            var year = now().UtcDateTime.Year;
            var races = (await Races($"{year}.json?limit=100", cancellation)).ToList();
            if (F1Schedule.Next(races, now()) is null)
                races.AddRange(await Races($"{year + 1}.json?limit=100", cancellation));
            var winners = await Races($"{year}/results/1.json?limit=100", cancellation);
            if (winners.Count == 0) winners = await Races($"{year - 1}/results/1.json?limit=100", cancellation);
            F1Podium? podium = null;
            if (winners.MaxBy(race => (race.Season, race.Round)) is { } winner)
                podium = F1Schedule.ParsePodium(await fetch($"{winner.Season}/{winner.Round}/results.json?limit=3", cancellation));
            cancellation.ThrowIfCancellationRequested();
            // A partial result response must not replace a known complete podium.
            Data = new(races, podium ?? Data?.Podium, now());
            Problem = null;
            nextRefresh = now().AddMinutes(F1Schedule.Pending(Data, now()) is null ? 30 : 5);
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(cachePath)!);
                var temporary = cachePath + ".tmp";
                File.WriteAllText(temporary, JsonSerializer.Serialize(Data));
                File.Move(temporary, cachePath, overwrite: true);
            }
            catch (Exception) { /* The fetched data is still usable for this session. */ }
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
        catch (Exception error)
        {
            if (!cancellation.IsCancellationRequested)
            {
                Problem = "Couldn't update";
                nextRefresh = now().AddMinutes(error is HttpRequestException { StatusCode: HttpStatusCode.TooManyRequests } ? 60 : 5);
            }
        }
        finally
        {
            refreshing = false;
            if (ReferenceEquals(lifetime, source))
            {
                Updating = false;
                Changed?.Invoke();
            }
            else if (Enabled) _ = RefreshAsync(); // switched off and back on during a request
        }
    }

    async Task<IReadOnlyList<F1Race>> Races(string endpoint, CancellationToken cancellation) => F1Schedule.ParseRaces(await fetch(endpoint, cancellation));

    static bool ValidCache(F1Data? data) => data?.Races is { } races && races.All(ValidRace)
        && (data.Podium is null || ValidRace(data.Podium.Race) && data.Podium.Drivers is { Count: 3 } drivers
            && drivers.All(driver => driver is not null && !string.IsNullOrWhiteSpace(driver.Name))
            && drivers.Select(driver => driver.Position).Order().SequenceEqual(new[] { 1, 2, 3 }));

    static bool ValidRace(F1Race? race) => race is not null && race.Season >= 1950 && race.Round > 0
        && !string.IsNullOrWhiteSpace(race.Name) && race.Sessions is { Count: > 0 } sessions
        && sessions.All(session => session is not null && !string.IsNullOrWhiteSpace(session.Name));

    static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(20), MaxResponseContentBufferSize = 1_048_576 };
        var version = typeof(F1Feed).Assembly.GetName().Version?.ToString(3) ?? "0.1.0";
        client.DefaultRequestHeaders.UserAgent.ParseAdd($"Ledge/{version}");
        return client;
    }

    static async Task<string> Fetch(string endpoint, CancellationToken cancellation)
    {
        await Task.Delay(300, cancellation); // Keep cold-start requests below Jolpica's four-per-second limit.
        using var response = await Http.GetAsync($"https://api.jolpi.ca/ergast/f1/{endpoint}", cancellation);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsStringAsync(cancellation);
    }

    internal void ShowDemo(F1Data data, string? problem = null)
    {
        Data = data;
        Problem = problem;
        Changed?.Invoke();
    }
}
