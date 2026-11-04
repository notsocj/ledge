using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Navigation;

namespace Ledge;

public partial class F1Page : UserControl
{
    F1Feed? feed;
    F1Data? rendered;
    string? raceKey;
    string? displayedZone;
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
        RaceName.Text = race?.Name ?? "F1 weekend";
        CircuitName.Text = race?.Circuit ?? (feed.Data is null ? "Countdown, schedule and podium" : "Waiting for the next schedule");
        CountdownLabel.Text = race?.Start > now ? "Race in" : "F1";
        RaceCountdown.Text = feed.Data is null ? (feed.Updating ? "Updating…" : "Unavailable") : F1Schedule.Countdown(race, now);
        Freshness.Text = feed.Updating ? "Updating…" : feed.Data is { } data
            ? $"{(feed.Problem is null ? "Updated" : "Saved")} {data.UpdatedAt.ToLocalTime():ddd HH:mm}" : "Waiting for connection";
        Freshness.ToolTip = feed.Problem is null ? "Jolpica publishes results after the race." : "Couldn't update. Showing the last saved schedule and results.";
        // Minute ticks update text only. Rows and the island's spring remain untouched.
        var zone = $"{TimeZoneInfo.Local.Id}|{TimeZoneInfo.Local.GetUtcOffset(now)}";
        if (ReferenceEquals(rendered, feed.Data) && raceKey == race?.Key && displayedZone == zone) return;
        rendered = feed.Data;
        raceKey = race?.Key;
        displayedZone = zone;
        RaceName.ToolTip = race is null ? null : $"{race.Name} · {race.Date:d MMM yyyy}";
        CircuitName.ToolTip = race?.Circuit;
        TimeZoneLabel.Text = "Local time";
        TimeZoneLabel.ToolTip = $"Session times in {TimeZoneInfo.Local.DisplayName}";
        SessionRows.Children.Clear();
        ScheduleEmpty.Visibility = race is null ? Visibility.Visible : Visibility.Collapsed;
        if (race is not null)
        {
            foreach (var session in race.Sessions)
            {
                var row = new Grid { Height = 20 };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(118) });
                row.ColumnDefinitions.Add(new ColumnDefinition());
                var label = new TextBlock { Text = session.Name, FontSize = 11,
                    FontWeight = session.Name == "Race" ? FontWeights.SemiBold : FontWeights.Normal, VerticalAlignment = VerticalAlignment.Center };
                var time = new TextBlock { Text = session.LocalTime, FontSize = 10.5, Foreground = (Brush)FindResource("Graphite"),
                    HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
                Grid.SetColumn(time, 1);
                row.Children.Add(label);
                row.Children.Add(time);
                SessionRows.Children.Add(row);
            }
        }
        PodiumRows.Children.Clear();
        PodiumRace.Text = feed.Data?.Podium is { } podium ? podium.Race.Name.Replace(" Grand Prix", "") : "";
        PodiumRace.ToolTip = feed.Data?.Podium is { } result ? $"{result.Race.Name} · {result.Race.Date:d MMM yyyy}" : null;
        PodiumEmpty.Visibility = feed.Data?.Podium is null ? Visibility.Visible : Visibility.Collapsed;
        foreach (var driver in feed.Data?.Podium?.Drivers ?? [])
        {
            var row = new Grid { Margin = new Thickness(0, 0, 0, 2) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(24) });
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.Children.Add(new TextBlock { Text = $"{driver.Position}", FontSize = 13, FontWeight = FontWeights.SemiBold,
                Foreground = (Brush)FindResource("Ash") });
            var details = new StackPanel();
            details.Children.Add(new TextBlock { Text = driver.Name, FontSize = 11, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis });
            details.Children.Add(new TextBlock { Text = driver.Team, FontSize = 9.5, Foreground = (Brush)FindResource("Ash"), TextTrimming = TextTrimming.CharacterEllipsis });
            Grid.SetColumn(details, 1);
            row.Children.Add(details);
            PodiumRows.Children.Add(row);
        }
    }

    void Source_Click(object sender, RequestNavigateEventArgs e)
    {
        Process.Start(new ProcessStartInfo("https://jolpi.ca/") { UseShellExecute = true });
        e.Handled = true;
    }
}
