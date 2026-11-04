using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace Ledge;

/// <summary>Picks a color from anywhere on screen and copies its hex code, keeping the last eight.</summary>
public sealed class ColorPicker
{
    const int Limit = 8;
    readonly List<Color> recent = [];

    public IReadOnlyList<Color> Recent => recent;
    public bool IsPicking { get; private set; }
    public event Action? Changed;
    /// <summary>A color was picked and copied.</summary>
    public event Action<Color>? Picked;

    public static string Hex(Color color) => $"#{color.R:X2}{color.G:X2}{color.B:X2}";

    public void Copy(Color color)
    {
        try { Clipboard.SetText(Hex(color)); } catch (System.Runtime.InteropServices.COMException) { }
        recent.Remove(color);
        recent.Insert(0, color);
        if (recent.Count > Limit) recent.RemoveAt(Limit);
        Changed?.Invoke();
    }

    /// <summary>Covers every screen with a nearly invisible window that catches the click, and shows
    /// the color under the pointer beside it. Esc or a right-click cancels.</summary>
    public void Start()
    {
        if (IsPicking) return;
        IsPicking = true;
        var swatch = new Border { Width = 22, Height = 22, CornerRadius = new CornerRadius(6), BorderBrush = new SolidColorBrush(Color.FromArgb(0x40, 0xFF, 0xFF, 0xFF)), BorderThickness = new Thickness(1) };
        var hex = new TextBlock { Foreground = Brushes.White, FontSize = 13, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 2, 0) };
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(swatch);
        row.Children.Add(hex);
        var loupe = new Border { Background = Brushes.Black, CornerRadius = new CornerRadius(12), Padding = new Thickness(6), Child = row, IsHitTestVisible = false };
        var canvas = new Canvas();
        canvas.Children.Add(loupe);
        var overlay = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0)), // invisible, but still catches the click
            Topmost = true,
            ShowInTaskbar = false,
            Cursor = Cursors.Cross,
            Content = canvas,
            FontFamily = (FontFamily)Application.Current.FindResource("Poppins"), // the island's font, in its own window
        };
        var current = Colors.Black;
        overlay.SourceInitialized += (_, _) =>
        {
            var (left, top, width, height) = Native.VirtualScreen();
            Native.SetWindowPos(new WindowInteropHelper(overlay).Handle, Native.HWND_TOPMOST, left, top, width, height, 0);
        };
        overlay.MouseMove += (_, _) =>
        {
            if (!Native.GetCursorPos(out var cursor)) return;
            current = Native.ScreenColor(cursor.X, cursor.Y);
            swatch.Background = new SolidColorBrush(current);
            hex.Text = Hex(current);
            // Beside the pointer, never on the pixel being read.
            var at = overlay.PointFromScreen(new Point(cursor.X, cursor.Y));
            Canvas.SetLeft(loupe, at.X + 18);
            Canvas.SetTop(loupe, at.Y + 18);
        };
        void Finish(bool pick)
        {
            if (!IsPicking) return;
            IsPicking = false;
            overlay.Close();
            if (!pick) return;
            Copy(current);
            Picked?.Invoke(current);
        }
        overlay.MouseLeftButtonUp += (_, _) => Finish(pick: true);
        overlay.MouseRightButtonUp += (_, _) => Finish(pick: false);
        overlay.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape) Finish(pick: false);
        };
        overlay.Deactivated += (_, _) => Finish(pick: false); // Alt+Tab away cancels
        overlay.Show();
        overlay.Activate(); // so Esc reaches it
    }
}
