using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Ledge;

public partial class ShelfPage : UserControl
{
    Shelf shelf = null!;

    public ShelfPage() => InitializeComponent();

    public void Attach(Shelf shelf)
    {
        this.shelf = shelf;
        shelf.Changed += Refresh;
        Refresh();
    }

    void Refresh()
    {
        List.Visibility = shelf.Files.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        Empty.Visibility = shelf.Files.Count > 0 ? Visibility.Collapsed : Visibility.Visible;
        Tiles.Children.Clear();
        foreach (var path in shelf.Files) Tiles.Children.Add(Tile(path));
    }

    UIElement Tile(string path)
    {
        var name = Path.GetFileName(path.TrimEnd('\\'));
        var icon = new Image { Source = IconFor(path), Width = 32, Height = 32, HorizontalAlignment = HorizontalAlignment.Center };
        var label = new TextBlock { Text = name, FontSize = 11, FontWeight = FontWeights.Medium, TextTrimming = TextTrimming.CharacterEllipsis, TextAlignment = TextAlignment.Center, Margin = new Thickness(0, 6, 0, 0) };
        var remove = new Button { Style = (Style)FindResource("Icon"), Width = 20, Height = 20, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top,
            Content = new TextBlock { Text = "", FontSize = 9, Style = (Style)FindResource("Glyph") }, ToolTip = "Take off the shelf" };
        remove.Click += (_, _) => shelf.Remove(path);
        var stack = new StackPanel { Margin = new Thickness(6, 10, 6, 6) };
        stack.Children.Add(icon);
        stack.Children.Add(label);
        var tile = new Grid { Width = 92, Height = 82, Background = Brushes.Transparent, ToolTip = path };
        tile.Children.Add(new Border { Background = (Brush)FindResource("Well"), CornerRadius = new CornerRadius(12), Margin = new Thickness(0, 0, 6, 6) });
        tile.Children.Add(stack);
        tile.Children.Add(remove);

        Point? pressedAt = null;
        tile.MouseLeftButtonDown += (_, e) =>
        {
            pressedAt = e.GetPosition(tile);
            if (e.ClickCount == 2) Open(path);
        };
        tile.MouseMove += (_, e) =>
        {
            // A small movement threshold, so a click doesn't start a drag.
            if (pressedAt is not { } start || e.LeftButton != MouseButtonState.Pressed || (e.GetPosition(tile) - start).Length < 6) return;
            pressedAt = null;
            DragDrop.DoDragDrop(tile, new DataObject(DataFormats.FileDrop, new[] { path }), DragDropEffects.Copy | DragDropEffects.Move | DragDropEffects.Link);
            shelf.Prune(); // dragged somewhere that moved it
        };
        tile.MouseLeftButtonUp += (_, _) => pressedAt = null;
        return tile;
    }

    static void Open(string path)
    {
        try
        {
            Process.Start(new ProcessStartInfo(path) { UseShellExecute = true })?.Dispose();
        }
        catch (Exception)
        {
            // Gone, or nothing is set to open it.
        }
    }

    /// <summary>The file's own icon, as Explorer shows it; folders and missing files get none.</summary>
    static ImageSource? IconFor(string path)
    {
        try
        {
            using var icon = System.Drawing.Icon.ExtractAssociatedIcon(path);
            if (icon is null) return null;
            var image = Imaging.CreateBitmapSourceFromHIcon(icon.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            image.Freeze();
            return image;
        }
        catch (Exception)
        {
            return null;
        }
    }

    void Clear_Click(object sender, RoutedEventArgs e) => shelf.Clear();
}
