using System.Windows;
using System.Windows.Controls;

namespace Ledge;

public partial class ClipboardPage : UserControl
{
    ClipboardHistory history = null!;

    public ClipboardPage() => InitializeComponent();

    public void Attach(ClipboardHistory history)
    {
        this.history = history;
        history.Changed += Refresh;
        Refresh();
    }

    void Refresh()
    {
        List.Visibility = history.Items.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        Empty.Visibility = history.Items.Count > 0 ? Visibility.Collapsed : Visibility.Visible;
        Rows.Children.Clear();
        foreach (var text in history.Items)
        {
            var row = new Button
            {
                Style = (Style)FindResource("Quiet"),
                Height = 30,
                Padding = new Thickness(10, 0, 10, 0),
                HorizontalContentAlignment = HorizontalAlignment.Left,
                ToolTip = text.Length > 400 ? text[..400] + "…" : text,
                // One line per copy: newlines and runs of spaces fold into single spaces.
                Content = new TextBlock { Text = string.Join(' ', text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)), TextTrimming = TextTrimming.CharacterEllipsis },
            };
            row.Click += (_, _) => history.Copy(text);
            Rows.Children.Add(row);
        }
    }

    void Clear_Click(object sender, RoutedEventArgs e) => history.Clear();
}
