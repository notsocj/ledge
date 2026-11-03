using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Ledge;

public partial class ColorPage : UserControl
{
    ColorPicker picker = null!;

    /// <summary>Asked to pick: the island gets out of the way first.</summary>
    public event Action? PickRequested;

    public ColorPage() => InitializeComponent();

    public void Attach(ColorPicker picker)
    {
        this.picker = picker;
        picker.Changed += Refresh;
        Refresh();
    }

    void Refresh()
    {
        RecentLabel.Visibility = picker.Recent.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        Swatches.Children.Clear();
        foreach (var color in picker.Recent)
        {
            var content = new StackPanel { Orientation = Orientation.Horizontal };
            content.Children.Add(new Border { Width = 16, Height = 16, CornerRadius = new CornerRadius(5), Background = new SolidColorBrush(color),
                BorderBrush = (Brush)FindResource("Rail"), BorderThickness = new Thickness(1), Margin = new Thickness(0, 0, 8, 0) });
            content.Children.Add(new TextBlock { Text = ColorPicker.Hex(color), VerticalAlignment = VerticalAlignment.Center });
            var swatch = new Button { Style = (Style)FindResource("Pill"), Height = 30, Padding = new Thickness(8, 0, 12, 0), Margin = new Thickness(0, 0, 6, 6), Content = content };
            swatch.Click += (_, _) => picker.Copy(color);
            Swatches.Children.Add(swatch);
        }
    }

    void Pick_Click(object sender, RoutedEventArgs e) => PickRequested?.Invoke();
}
