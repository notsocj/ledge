using System.Diagnostics;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Navigation;
using System.Windows.Shapes;

namespace Ledge;

public partial class F1Page : UserControl
{
    F1Feed? feed;
    F1Data? rendered;
    string? raceKey;
    string? displayedZone;
    int renderedNext = -2;

    /// <summary>Gold, silver and bronze, muted so they sit quietly on black.</summary>
    static readonly Brush[] Medals =
    [
        Frozen(Color.FromRgb(0xE8, 0xC5, 0x6A)),
        Frozen(Color.FromRgb(0xCB, 0xD0, 0xD8)),
        Frozen(Color.FromRgb(0xD0, 0x93, 0x63)),
    ];

    public F1Page() => InitializeComponent();

    public void Attach(F1Feed feed)
    {
        this.feed = feed;
        feed.Changed += Refresh;
        Refresh();
    }

    public void Refresh() => RefreshAt(DateTimeOffset.UtcNow);

    internal void RefreshAt(DateTimeOffset now)
    {
        if (feed is null) return;
        var race = F1Schedule.Focus(feed.Data, now);
        RaceName.Text = race?.Name ?? "Formula 1";
        CircuitName.Text = race is null
            ? (feed.Data is null ? "Countdown, schedule and podium" : "Waiting for the next schedule")
            : $"Round {race.Round} · {race.Circuit}";

        var counting = feed.Data is not null && race?.Start > now;
        RaceCountdown.Text = feed.Data is null ? (feed.Updating ? "Updating…" : "Unavailable") : F1Schedule.Countdown(race, now);
        // A countdown is the biggest thing here; words like "Results pending" stay smaller.
        RaceCountdown.FontSize = counting ? 24 : 15;
        CountdownLabel.Text = counting ? "to lights out" : race?.Start <= now ? "Race status" : "";
        CountdownLabel.Visibility = CountdownLabel.Text.Length > 0 ? Visibility.Visible : Visibility.Collapsed;

        Freshness.Text = Freshness_(now);
        Freshness.ToolTip = feed.Problem is null
            ? $"Session times in {TimeZoneInfo.Local.DisplayName}. Jolpica publishes results after the race."
            : "Couldn't update. Showing the last saved schedule and results.";

        // Minute ticks only update text. Rows are rebuilt when the data, the weekend, the time zone or the
        // next session changes, so the island's spring never replays.
        var next = race is null ? -1 : NextSession(race, now);
        var zone = $"{TimeZoneInfo.Local.Id}|{TimeZoneInfo.Local.GetUtcOffset(now)}";
        if (ReferenceEquals(rendered, feed.Data) && raceKey == race?.Key && displayedZone == zone && renderedNext == next)
        {
            UpdateNextChip(race, next, now);
            return;
        }
        rendered = feed.Data;
        raceKey = race?.Key;
        displayedZone = zone;
        renderedNext = next;
        RaceName.ToolTip = race is null ? null : $"{race.Name} · {race.Date:d MMM yyyy}";
        CircuitName.ToolTip = race?.Circuit;

        SessionRows.Children.Clear();
        ScheduleEmpty.Visibility = race is null || race.Sessions.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        if (race is not null)
            for (var index = 0; index < race.Sessions.Count; index++)
                SessionRows.Children.Add(SessionRow(race.Sessions[index], done: next == -1 || index < next, isNext: index == next, now));

        PodiumRows.Children.Clear();
        var podium = feed.Data?.Podium;
        PodiumRace.Text = podium is null ? "Last podium" : $"Last podium · {podium.Race.Name.Replace(" Grand Prix", "")}";
        PodiumRace.ToolTip = podium is null ? null : $"{podium.Race.Name} · {podium.Race.Date:d MMM yyyy}";
        PodiumEmpty.Visibility = podium is null ? Visibility.Visible : Visibility.Collapsed;
        foreach (var driver in podium?.Drivers ?? []) PodiumRows.Children.Add(PodiumRow(driver));
    }

    /// <summary>The first session that hasn't started, or -1 once the whole weekend has.</summary>
    static int NextSession(F1Race race, DateTimeOffset now)
    {
        for (var index = 0; index < race.Sessions.Count; index++)
            if (race.Sessions[index].Start is not { } start || start > now) return index;
        return -1;
    }

    string Freshness_(DateTimeOffset now)
    {
        if (feed!.Updating) return "Updating…";
        if (feed.Data is not { } data) return "Waiting for connection";
        var age = now - data.UpdatedAt;
        var stamp = age < TimeSpan.FromMinutes(1) ? "just now"
            : age < TimeSpan.FromHours(1) ? $"{(int)age.TotalMinutes}m ago"
            : age < TimeSpan.FromDays(1) ? $"{(int)age.TotalHours}h ago"
            : data.UpdatedAt.ToLocalTime().ToString("ddd d MMM", CultureInfo.CurrentCulture);
        return $"Local times · {(feed.Problem is null ? "Updated" : "Saved")} {stamp}";
    }

    TextBlock? nextChipText;

    /// <summary>One session: a status mark, its name, then its day and time in aligned columns.</summary>
    UIElement SessionRow(F1Session session, bool done, bool isNext, DateTimeOffset now)
    {
        var isRace = session.Name == "Race";
        var row = new Grid { Height = 22, Margin = new Thickness(0, 0, 0, 1) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(22) });
        row.ColumnDefinitions.Add(new ColumnDefinition());
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(52) });

        // Done: a small filled dot. Next: green. Later: a hollow ring. The race: a flag.
        FrameworkElement mark = isRace && !done
            ? new TextBlock { Text = "", Style = (Style)FindResource("Glyph"), FontSize = 11, Foreground = isNext ? (Brush)FindResource("Live") : Brushes.White }
            : new Ellipse
            {
                Width = 6, Height = 6,
                Fill = done ? (Brush)FindResource("Rail") : isNext ? (Brush)FindResource("Live") : Brushes.Transparent,
                Stroke = done || isNext ? null : (Brush)FindResource("Graphite"), StrokeThickness = 1,
            };
        mark.HorizontalAlignment = HorizontalAlignment.Center;
        mark.VerticalAlignment = VerticalAlignment.Center;

        var emphasis = isNext || isRace && !done;
        var name = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        name.Children.Add(new TextBlock
        {
            Text = session.Name, FontSize = 12.5, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis,
            FontWeight = emphasis ? FontWeights.SemiBold : FontWeights.Medium,
            Foreground = done ? (Brush)FindResource("Ash") : emphasis ? Brushes.White : (Brush)FindResource("Graphite"),
        });
        if (isNext && session.Start is { } start)
        {
            // How long until it starts, on a small green chip; updated each minute without rebuilding the row.
            nextChipText = new TextBlock { Text = Until(start, now), FontSize = 10.5, FontWeight = FontWeights.SemiBold, Foreground = (Brush)FindResource("Live") };
            name.Children.Add(new Border
            {
                Background = Frozen(Color.FromArgb(0x26, 0x30, 0xD1, 0x58)), CornerRadius = new CornerRadius(8),
                Padding = new Thickness(7, 1, 7, 1), Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center, Child = nextChipText,
            });
        }

        var local = session.Start?.ToLocalTime();
        var timeColor = done ? (Brush)FindResource("Ash") : Brushes.White;
        var day = new TextBlock
        {
            Text = local?.ToString("ddd d", CultureInfo.CurrentCulture) ?? session.Date.ToString("ddd d", CultureInfo.CurrentCulture),
            FontSize = 12, FontWeight = FontWeights.Medium, Foreground = done ? (Brush)FindResource("Ash") : (Brush)FindResource("Graphite"),
            VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(8, 0, 10, 0),
        };
        var time = new TextBlock
        {
            Text = local?.ToString("t", CultureInfo.CurrentCulture) ?? "TBC", FontSize = 12,
            FontWeight = emphasis ? FontWeights.SemiBold : FontWeights.Medium, Foreground = timeColor,
            VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Right,
        };
        Grid.SetColumn(name, 1);
        Grid.SetColumn(day, 2);
        Grid.SetColumn(time, 3);
        foreach (var child in new UIElement[] { mark, name, day, time }) row.Children.Add(child);
        var plate = new Border
        {
            Child = row, CornerRadius = new CornerRadius(8), Padding = new Thickness(0, 0, 8, 0),
            Background = isNext ? (Brush)FindResource("Well") : Brushes.Transparent,
            ToolTip = $"{session.Name}, {session.LocalTime}",
        };
        return plate;
    }

    void UpdateNextChip(F1Race? race, int next, DateTimeOffset now)
    {
        if (nextChipText is null || race is null || next < 0 || race.Sessions[next].Start is not { } start) return;
        nextChipText.Text = Until(start, now);
    }

    /// <summary>"in 2d 4h", "in 3h 20m", "in 12m".</summary>
    static string Until(DateTimeOffset start, DateTimeOffset now)
    {
        var minutes = Math.Max(1, (int)Math.Ceiling((start - now).TotalMinutes));
        return minutes >= 1440 ? $"in {minutes / 1440}d {minutes % 1440 / 60}h"
            : minutes >= 60 ? $"in {minutes / 60}h {minutes % 60}m" : $"in {minutes}m";
    }

    /// <summary>A podium place on one line: a medal-colored badge, the driver's surname, and the team, quieter, on the right.</summary>
    UIElement PodiumRow(F1Driver driver)
    {
        var row = new Grid { Height = 22, Margin = new Thickness(0, 0, 0, 6), ToolTip = $"{driver.Position}. {driver.Name}, {driver.Team}" };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(28) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition());
        var badge = new Border
        {
            Width = 20, Height = 20, CornerRadius = new CornerRadius(10), VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Left,
            Background = driver.Position is >= 1 and <= 3 ? Medals[driver.Position - 1] : (Brush)FindResource("Rail"),
            Child = new TextBlock { Text = $"{driver.Position}", FontSize = 10.5, FontWeight = FontWeights.Bold, Foreground = Brushes.Black,
                HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 1, 0, 0) },
        };
        var surname = new TextBlock { Text = Surname(driver.Name), Style = (Style)FindResource("HeadlineText"), Foreground = Brushes.White, VerticalAlignment = VerticalAlignment.Center };
        var team = new TextBlock { Text = driver.Team, Style = (Style)FindResource("CaptionText"), HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(8, 0, 0, 0) };
        Grid.SetColumn(surname, 1);
        Grid.SetColumn(team, 2);
        row.Children.Add(badge);
        row.Children.Add(surname);
        row.Children.Add(team);
        return row;
    }

    /// <summary>"Andrea Kimi Antonelli" reads as "Antonelli", as on timing screens.</summary>
    internal static string Surname(string name) => name.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries) is { Length: > 0 } parts ? parts[^1] : name;

    static SolidColorBrush Frozen(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    void Source_Click(object sender, RequestNavigateEventArgs e)
    {
        Process.Start(new ProcessStartInfo("https://jolpi.ca/") { UseShellExecute = true });
        e.Handled = true;
    }
}
