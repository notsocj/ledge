using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Ledge;

public partial class CalendarPage : UserControl
{
    CalendarFeed feed = null!;
    bool hasLink;

    /// <summary>A link was pasted (or removed, with null); the island saves it and fetches.</summary>
    public event Action<string?>? LinkChanged;

    public CalendarPage() => InitializeComponent();

    public void Attach(CalendarFeed feed, bool hasLink)
    {
        this.feed = feed;
        feed.Changed += Refresh;
        SetHasLink(hasLink);
    }

    public void SetHasLink(bool hasLink)
    {
        this.hasLink = hasLink;
        Refresh();
    }

    void Refresh()
    {
        List.Visibility = hasLink ? Visibility.Visible : Visibility.Collapsed;
        Setup.Visibility = hasLink ? Visibility.Collapsed : Visibility.Visible;
        Problem.Text = feed.Problem ?? "";
        Rows.Children.Clear();
        var now = DateTime.Now;
        var upcoming = feed.Meetings.Where(meeting => meeting.End > now).ToList();
        if (hasLink && upcoming.Count == 0)
            Rows.Children.Add(new TextBlock { Text = feed.Problem is null ? "Nothing else today or tomorrow." : "", Style = (Style)FindResource("BodyText"), Margin = new Thickness(10, 4, 0, 0) });
        foreach (var day in upcoming.GroupBy(meeting => meeting.Start.Date < now.Date ? now.Date : meeting.Start.Date))
        {
            Rows.Children.Add(new TextBlock { Text = day.Key == now.Date ? "Today" : "Tomorrow", Style = (Style)FindResource("LabelText"), Margin = new Thickness(10, 6, 0, 2) });
            foreach (var meeting in day) Rows.Children.Add(Row(meeting, now));
        }
    }

    UIElement Row(Meeting meeting, DateTime now)
    {
        var row = new Grid { Height = 30, Margin = new Thickness(10, 0, 6, 0) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(64) });
        row.ColumnDefinitions.Add(new ColumnDefinition());
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var live = meeting.Start <= now && !meeting.AllDay;
        var time = new TextBlock
        {
            Text = meeting.AllDay ? "All day" : live ? "Now" : meeting.Start.ToString("t"),
            Style = (Style)FindResource("RowText"),
            Foreground = live ? (Brush)FindResource("Live") : (Brush)FindResource("Graphite"),
        };
        // The meeting's name is what you look for, so it's one step heavier than its time.
        var title = new TextBlock { Text = meeting.Title, Style = (Style)FindResource("HeadlineText"), VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(title, 1);
        row.Children.Add(time);
        row.Children.Add(title);
        if (meeting.JoinLink is { } link)
        {
            var join = new Button { Style = (Style)FindResource("Pill"), Content = "Join", Height = 24, ToolTip = link };
            join.Click += (_, _) => Process.Start(new ProcessStartInfo(link) { UseShellExecute = true })?.Dispose();
            Grid.SetColumn(join, 2);
            row.Children.Add(join);
        }
        return row;
    }

    void Paste_Click(object sender, RoutedEventArgs e)
    {
        string? text = null;
        try { text = Clipboard.GetText(); } catch (System.Runtime.InteropServices.COMException) { }
        if (CalendarFeed.Normalize(text) is not { } link)
        {
            PasteProblem.Text = "The clipboard doesn't have a calendar link. Copy the ICS link first.";
            return;
        }
        PasteProblem.Text = "";
        LinkChanged?.Invoke(link);
    }

    void Remove_Click(object sender, RoutedEventArgs e) => LinkChanged?.Invoke(null);
}
