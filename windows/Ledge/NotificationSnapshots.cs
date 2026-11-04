using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Ledge;

/// <summary>Native, deterministic captures of the production island morph. No live tools, preferences or
/// clipboard are used. Motion advances through the same model as the on-screen control.</summary>
static class NotificationSnapshots
{
    static readonly Size SceneSize = new(480, 160);
    const double FramesPerSecond = 30;

    static readonly (string Name, NotificationContent Content)[] Samples =
    [
        ("agent-done", new("Codex", "ledge", "Done", "\uE943", NotificationTone.Mint)),
        ("agent-waiting", new("Claude Code", "website", "Needs you", "\uE943", NotificationTone.Iris)),
        ("meeting", new("Meeting soon", "Design review", "2 min", "\uE787", NotificationTone.Iris)),
        ("battery", new("Battery", "Power connected", "54%", "\uE945", NotificationTone.Mint)),
        ("microphone", new("Microphone", "Recording app", "On", "\uE720", NotificationTone.Amber)),
        ("color", new("Color picked", "Copied to clipboard", "#7BC4A4", "\uE790", Swatch: Color.FromRgb(0x7B, 0xC4, 0xA4), Immediate: true)),
        ("long-context", new("Meeting soon", "Product design review and Windows release planning", "12 min", "\uE787", NotificationTone.Iris)),
        ("long-title", new("A notification title that should stay inside the capsule", "A long project name with several nested folders", "Needs you", "\uE943", NotificationTone.Iris)),
    ];

    /// <param name="includeFrames">The standalone command includes 195 numbered frames; ordinary CI
    /// page snapshots only need the static captures and contact sheets.</param>
    public static void Run(string folder, bool includeFrames = true)
    {
        VerifySingleSurface();
        Directory.CreateDirectory(folder);
        var cards = new List<(string Label, BitmapSource Image)>();
        foreach (var (name, content) in Samples)
        {
            var scene = new PreviewScene();
            scene.Show(content, reduced: false);
            for (var frame = 0; frame < 90; frame++) scene.Advance(1 / FramesPerSecond);
            var image = Render(scene.Canvas, SceneSize);
            Save(image, Path.Combine(folder, $"4-notification-{name}.png"));
            cards.Add((name.Replace('-', ' '), image));
        }
        SaveSheet(cards, "Windows island notifications", Path.Combine(folder, "4-notifications.png"));

        CaptureMotion(folder, "entry-exit", 90, false, includeFrames,
            [(3, Samples[1].Content), (30, Samples[0].Content), (54, null)],
            [3, 4, 6, 10, 30, 54, 56, 60]);
        CaptureMotion(folder, "interruption", 60, false, includeFrames,
            [(3, Samples[1].Content), (15, null), (17, Samples[0].Content), (30, null),
             (36, Samples[3].Content), (39, null)],
            [3, 15, 16, 17, 19, 36, 39, 45]);
        CaptureMotion(folder, "reduced-motion", 45, true, includeFrames,
            [(3, Samples[1].Content), (18, Samples[0].Content), (30, null)],
            [3, 4, 6, 18, 30, 31, 33, 38]);
    }

    /// <summary>The same native window and surface stay mounted through entry, replacement and
    /// dismissal. No app services or personal settings are involved.</summary>
    static void VerifySingleSurface()
    {
        var app = Application.Current;
        var previousShutdown = app.ShutdownMode;
        var previousMain = app.MainWindow;
        var previousWindowCount = app.Windows.Count;
        var scene = new PreviewScene();
        var surface = scene.Surface;
        var window = new Window
        {
            Content = scene.Canvas, Width = SceneSize.Width, Height = SceneSize.Height,
            Left = -10000, Top = -10000, WindowStyle = WindowStyle.None,
            ShowActivated = false, ShowInTaskbar = false,
        };
        app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        try
        {
            window.Show();
            var handle = new WindowInteropHelper(window).Handle;
            Render(scene.Canvas, SceneSize);
            if (scene.Frame.Children.OfType<IslandSurface>().Count() != 1 || surface.Geometry.Bounds.Width != 180)
                throw new InvalidOperationException("The compact island must have one surface.");
            scene.Show(Samples[0].Content, reduced: false);
            for (var frame = 0; frame < 5; frame++) scene.Advance(1 / FramesPerSecond);
            scene.Dismiss(reduced: false);
            scene.Advance(1 / FramesPerSecond);
            scene.Show(Samples[1].Content, reduced: false);
            for (var frame = 0; frame < 90; frame++) scene.Advance(1 / FramesPerSecond);
            Render(scene.Canvas, SceneSize);
            if (!ReferenceEquals(scene.Surface, surface) || surface.Geometry.Bounds.Width != 364
                || scene.Capsule.Visibility != Visibility.Visible || scene.ContentClip.Clip != surface.Geometry)
                throw new InvalidOperationException("A replacement alert must use the same growing surface and content clip.");
            if (app.Windows.Count != previousWindowCount + 1 || window.OwnedWindows.Count != 0
                || new WindowInteropHelper(window).Handle != handle)
                throw new InvalidOperationException("Notification presentation must keep one native window.");
            scene.Dismiss(reduced: false);
            for (var frame = 0; frame < 90; frame++) scene.Advance(1 / FramesPerSecond);
            Render(scene.Canvas, SceneSize);
            if (!ReferenceEquals(scene.Surface, surface) || surface.Geometry.Bounds.Width != 180
                || scene.Motion.Height != 32 || scene.Capsule.Visibility != Visibility.Collapsed
                || new WindowInteropHelper(window).Handle != handle)
                throw new InvalidOperationException("Dismissal must restore the same compact island, not remove it.");
            Console.WriteLine("Single island: one native window, retained surface, replacement, clipping and compact restoration passed.");
        }
        finally
        {
            window.Close();
            app.MainWindow = previousMain;
            app.ShutdownMode = previousShutdown;
        }
    }

    static void CaptureMotion(string folder, string name, int count, bool reduced, bool includeFrames,
                              (int Frame, NotificationContent? Content)[] updates, int[] keyframes)
    {
        var scene = new PreviewScene();
        var frames = Path.Combine(folder, name + "-frames");
        if (includeFrames)
        {
            Directory.CreateDirectory(frames);
            // Only this renderer's numbered PNGs are replaced; unrelated output is left alone.
            foreach (var file in Directory.EnumerateFiles(frames, "*.png"))
            {
                var stem = Path.GetFileNameWithoutExtension(file);
                if (stem.Length == 4 && stem.All(char.IsDigit)) File.Delete(file);
            }
        }
        var cards = new List<(string Label, BitmapSource Image)>();
        for (var frame = 0; frame < count; frame++)
        {
            foreach (var update in updates.Where(update => update.Frame == frame))
            {
                if (update.Content is { } content) scene.Show(content, reduced);
                else scene.Dismiss(reduced);
            }
            scene.Advance(1 / FramesPerSecond);
            if (!includeFrames && !keyframes.Contains(frame)) continue;
            var image = Render(scene.Canvas, SceneSize);
            if (includeFrames) Save(image, Path.Combine(frames, $"{frame:0000}.png"));
            if (keyframes.Contains(frame)) cards.Add(($"{(frame + 1) / FramesPerSecond:0.00}s", image));
        }
        SaveSheet(cards, name.Replace('-', ' '), Path.Combine(folder, $"4-notification-{name}.png"));
    }

    /// <summary>The same surface, geometry clipping and reveal as IslandWindow, driven explicitly
    /// at 30 fps so a preview can be rendered without starting live services.</summary>
    sealed class PreviewScene
    {
        static readonly Size CompactSize = new(180, 32), NotificationSize = new(364, 64);
        public Canvas Canvas { get; } = new() { Width = SceneSize.Width, Height = SceneSize.Height, Background = Backdrop() };
        public Grid Frame { get; } = new();
        public Grid ContentClip { get; } = new();
        public IslandSurface Surface { get; } = new();
        public NotificationCapsule Capsule { get; } = new()
        {
            AnimateAutomatically = false, HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Top,
        };
        public IslandMotion Motion { get; } = new(CompactSize);
        bool immediate;

        public PreviewScene()
        {
            ApplyType(Canvas);
            ContentClip.Children.Add(Capsule);
            Frame.Children.Add(Surface);
            Frame.Children.Add(ContentClip);
            System.Windows.Controls.Canvas.SetTop(Frame, 8);
            Canvas.Children.Add(Frame);
            Apply();
        }

        public void Show(NotificationContent content, bool reduced)
        {
            immediate = content.Immediate;
            Capsule.Show(content, reduceMotion: reduced);
            Motion.Retarget(NotificationSize, notification: true, reduceMotion: reduced, immediate: immediate);
            Apply();
        }

        public void Dismiss(bool reduced)
        {
            Capsule.Dismiss(reduceMotion: reduced);
            Motion.Retarget(CompactSize, reduceMotion: reduced, immediate: immediate);
            Apply();
        }

        public void Advance(double seconds)
        {
            Capsule.Advance(seconds);
            Motion.Step(seconds);
            Apply();
        }

        void Apply()
        {
            var size = new Size(Motion.Width, Motion.Height);
            Frame.Width = size.Width;
            Frame.Height = size.Height;
            ContentClip.Width = size.Width;
            ContentClip.Height = size.Height;
            System.Windows.Controls.Canvas.SetLeft(Frame, (SceneSize.Width - size.Width) / 2);
            Surface.Update(size, Motion.CornerRadius, Motion.Bend, Math.Abs(Motion.Bend) / 16);
            ContentClip.Clip = Surface.Geometry;
            Capsule.Reveal = Motion.NotificationReveal;
        }
    }

    static void SaveSheet(IReadOnlyList<(string Label, BitmapSource Image)> cards, string title, string path)
    {
        const int columns = 2;
        const double heading = 52, label = 24;
        var rowHeight = SceneSize.Height + label;
        var size = new Size(SceneSize.Width * columns, heading + Math.Ceiling(cards.Count / (double)columns) * rowHeight);
        var canvas = new Canvas { Width = size.Width, Height = size.Height, Background = Backdrop() };
        ApplyType(canvas);
        var titleText = new TextBlock { Text = title, FontSize = 20, FontWeight = FontWeights.SemiBold, Foreground = Brushes.Black };
        Canvas.SetLeft(titleText, 26);
        Canvas.SetTop(titleText, 14);
        canvas.Children.Add(titleText);
        for (var index = 0; index < cards.Count; index++)
        {
            var x = index % columns * SceneSize.Width;
            var y = heading + index / columns * rowHeight;
            var image = new Image { Source = cards[index].Image, Width = SceneSize.Width, Height = SceneSize.Height };
            Canvas.SetLeft(image, x);
            Canvas.SetTop(image, y + label);
            canvas.Children.Add(image);
            var text = new TextBlock { Text = cards[index].Label, FontSize = 12, Foreground = new SolidColorBrush(Color.FromRgb(0x45, 0x4A, 0x54)) };
            Canvas.SetLeft(text, x + 26);
            Canvas.SetTop(text, y + 2);
            canvas.Children.Add(text);
        }
        Save(Render(canvas, size), path);
    }

    static Brush Backdrop() => new LinearGradientBrush(Color.FromRgb(0xE0, 0xE5, 0xED), Color.FromRgb(0xC4, 0xCE, 0xDB), 90);

    static void ApplyType(DependencyObject element)
    {
        TextElement.SetFontFamily(element, (FontFamily)Application.Current.FindResource("Poppins"));
        TextElement.SetFontSize(element, 12.5);
        TextElement.SetForeground(element, Brushes.White);
    }

    static BitmapSource Render(FrameworkElement element, Size size)
    {
        element.Measure(size);
        element.Arrange(new Rect(size));
        element.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)(size.Width * 2), (int)(size.Height * 2), 192, 192, PixelFormats.Pbgra32);
        bitmap.Render(element);
        bitmap.Freeze();
        return bitmap;
    }

    static void Save(BitmapSource image, string path)
    {
        var png = new PngBitmapEncoder();
        png.Frames.Add(BitmapFrame.Create(image));
        using var file = File.Create(path);
        png.Save(file);
    }
}
