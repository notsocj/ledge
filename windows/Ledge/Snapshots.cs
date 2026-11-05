using System.IO;
using System.Windows;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Ledge;

/// <summary><c>Ledge.exe --snapshot &lt;folder&gt;</c> renders the open island off-screen on every tab and
/// each setup step, with made-up data, writes them as PNGs at 200% and quits. Nothing you've set is
/// read or changed. For reviewing the design without a Windows PC to hand, as the Mac app's
/// --snapshot does; GitHub Actions runs it on every push to windows/.</summary>
static class Snapshots
{
    static readonly Size OpenSize = new(560, 220), SetupSize = new(560, 320);
    const double Backdrop = 32; // the wallpaper-ish margin around the island in each picture

    public static void Run(string folder)
    {
        Directory.CreateDirectory(folder);
        var tools = new Tools(Dispatcher.CurrentDispatcher);
        ShowDemo(tools);

        // Developer and Designer between them switch on every tab.
        var settings = new Settings { SetupDone = true, Personas = [Persona.Developer, Persona.Designer], CalendarLink = "https://example.com/demo.ics" };
        var panel = new OpenPanel { Width = OpenSize.Width, Height = OpenSize.Height, AnimateTabs = false };
        panel.Attach(tools, settings);
        panel.ShowPorts([new(3000, 0, "node"), new(5173, 0, "node"), new(8000, 0, "python"), new(5432, 0, "postgres")]);

        panel.HomeTab.IsChecked = true;
        Save(panel, OpenSize, Path.Combine(folder, "1-home.png"));
        HomeVariants(folder);
        F1Variants(folder);
        foreach (var (tool, name) in new[] { (Tool.Calendar, "calendar"), (Tool.Timer, "timer"), (Tool.Ports, "ports"),
                     (Tool.Clipboard, "clipboard"), (Tool.Shelf, "shelf"), (Tool.ColorPicker, "color") })
        {
            panel.ShowTab(tool);
            Save(panel, OpenSize, Path.Combine(folder, $"2-{name}.png"));
        }

        var setup = new SetupView { Width = SetupSize.Width, Height = SetupSize.Height };
        setup.Begin(new Settings { Personas = [Persona.Developer, Persona.Designer] }); // two picks, so the numbered badges show
        foreach (var step in Enum.GetValues<SetupView.Step>())
        {
            setup.Show(step);
            Save(setup, SetupSize, Path.Combine(folder, $"3-setup-{(int)step + 1}-{step.ToString().ToLowerInvariant()}.png"));
        }
        NotificationSnapshots.Run(folder, includeFrames: false);
    }

    /// <summary>Real Home layouts with long and missing content. Separate tools keep every variant
    /// independent; none is started, and no real media session or calendar is read.</summary>
    static void HomeVariants(string folder)
    {
        var artwork = DemoArtwork();
        foreach (var variant in new[] { "long-title", "empty", "media-only", "calendar-only" })
        {
            var tools = new Tools(Dispatcher.CurrentDispatcher);
            var settings = new Settings { SetupDone = true, Personas = [Persona.Essentials], CalendarLink = "https://example.com/demo.ics" };
            if (variant != "empty")
                tools.NowPlaying.ShowDemo("Hold On, We're Going Home Before the Morning", "Northbound and the Afterglow Orchestra", artwork);
            if (variant == "media-only")
            {
                settings.Off = [Tool.Calendar, Tool.KeepAwake];
                settings.CalendarLink = null;
            }
            else
            {
                var now = DateTime.Now;
                tools.Battery.ShowDemo(76, onPower: false);
                tools.Calendar.ShowDemo([new("Design review", now.AddMinutes(-5), now.AddMinutes(35), false, null)]);
            }
            if (variant == "calendar-only") settings.Off = [Tool.Media];
            var panel = new OpenPanel { Width = OpenSize.Width, Height = OpenSize.Height, AnimateTabs = false };
            panel.Attach(tools, settings);
            Save(panel, OpenSize, Path.Combine(folder, $"1-home-{variant}.png"));
        }
    }

    /// <summary>Isolated F1 fixtures: snapshots never start the feed or make requests.</summary>
    static void F1Variants(string folder)
    {
        var now = DateTimeOffset.UtcNow;
        var start = now.AddDays(3).AddHours(4);
        var day = DateOnly.FromDateTime(start.UtcDateTime);
        var weekend = new F1Race(2026, 20, "São Paulo Grand Prix", "Autódromo José Carlos Pace", day, start,
        [
            new("Practice 1", day.AddDays(-2), start.AddDays(-2).AddHours(-3)),
            new("Sprint qualifying", day.AddDays(-2), start.AddDays(-2).AddHours(1)),
            new("Sprint", day.AddDays(-1), start.AddDays(-1).AddHours(-3)),
            new("Qualifying", day.AddDays(-1), start.AddDays(-1).AddHours(1)),
            new("Race", day, start),
        ]);
        var previous = weekend with { Round = 19, Name = "Mexico City Grand Prix", Start = start.AddDays(-7), Date = day.AddDays(-7) };
        var podium = new F1Podium(previous, [new(1, "Lando Norris", "McLaren"), new(2, "Charles Leclerc", "Ferrari"), new(3, "Max Verstappen", "Red Bull")]);
        // Mid-weekend: practice and sprint qualifying done, the sprint next.
        var underway = weekend with
        {
            Start = now.AddDays(1).AddHours(5),
            Sessions = weekend.Sessions.Select(session => session with { Start = session.Start?.AddDays(-2).AddHours(1) }).ToList(),
        };
        foreach (var variant in new[] { "weekend", "underway", "results-pending", "saved", "empty" })
        {
            var tools = new Tools(Dispatcher.CurrentDispatcher);
            var race = variant switch { "results-pending" => weekend with { Start = now.AddHours(-2) }, "underway" => underway, _ => weekend };
            if (variant != "empty") tools.F1.ShowDemo(new([race], podium, now.AddMinutes(-12)), variant == "saved" ? "Couldn't update" : null);
            var panel = new OpenPanel { Width = 560, Height = 260, AnimateTabs = false };
            panel.Attach(tools, new Settings { SetupDone = true, Personas = [Persona.Essentials], F1Enabled = true });
            panel.ShowTab(Tool.F1);
            Save(panel, new Size(560, 260), Path.Combine(folder, $"2-f1-{variant}.png"));
        }
    }

    /// <summary>Made-up content for every tool, so no one's real music, meetings or clipboard ends up in a picture.</summary>
    static void ShowDemo(Tools tools)
    {
        tools.NowPlaying.ShowDemo("Afterglow", "Northbound", DemoArtwork());
        tools.Battery.ShowDemo(76, onPower: false);
        tools.Countdown.Start(25);

        var now = DateTime.Now;
        var today = now.Date;
        tools.Calendar.ShowDemo(
        [
            new("Design review", now.AddMinutes(-10), now.AddMinutes(35), false, "https://teams.microsoft.com/l/meetup-join/demo"),
            new("1:1 with Sam", now.AddHours(2), now.AddHours(2.5), false, "https://zoom.us/j/demo"),
            new("Ship the Windows build", now.AddHours(4), now.AddHours(5), false, null),
            new("Standup", today.AddDays(1).AddHours(9.5), today.AddDays(1).AddHours(9.75), false, "https://meet.google.com/demo"),
        ]);

        // The newest copy goes on top, so these are added oldest first.
        foreach (var text in new[] { "Meet at 3 instead?", "SELECT * FROM users WHERE plan = 'pro';", "https://keepledge.vercel.app", "npm run dev" })
            tools.Clipboard.Remember(text);

        // Real (empty) files, so the shelf shows Explorer's icons for them.
        var shelfFolder = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), "Ledge snapshot shelf")).FullName;
        var files = new[] { "Brief.pdf", "Hero.png", "Logo.svg", "Assets.zip", "Notes.txt" }.Select(name => Path.Combine(shelfFolder, name)).ToList();
        foreach (var file in files) File.WriteAllBytes(file, []);
        tools.Shelf.Add(files);

        foreach (var hex in new[] { "#7BC4A4", "#E85D75", "#2E2A4F", "#F2B880", "#43689A" })
            tools.ColorPicker.Copy((Color)ColorConverter.ConvertFromString(hex));
    }

    /// <summary>Album art drawn in code: a low sun over dark hills.</summary>
    static ImageSource DemoArtwork()
    {
        var visual = new DrawingVisual();
        using (var drawing = visual.RenderOpen())
        {
            var sky = new LinearGradientBrush(new GradientStopCollection
            {
                new(Color.FromRgb(0x21, 0x1F, 0x4D), 0),
                new(Color.FromRgb(0x85, 0x3D, 0x78), 0.55),
                new(Color.FromRgb(0xFA, 0x9E, 0x61), 1),
            }, 90);
            drawing.DrawRectangle(sky, null, new Rect(0, 0, 176, 176));
            drawing.DrawEllipse(new SolidColorBrush(Color.FromArgb(0xF2, 0xFF, 0xDB, 0x9E)), null, new Point(88, 100), 27, 27);
            var hills = Geometry.Parse("M0,176 L0,108 C35,88 65,118 97,112 C130,104 152,92 176,102 L176,176 Z");
            drawing.DrawGeometry(new SolidColorBrush(Color.FromRgb(0x14, 0x12, 0x29)), null, hills);
        }
        var image = new RenderTargetBitmap(176, 176, 96, 96, PixelFormats.Pbgra32);
        image.Render(visual);
        image.Freeze();
        return image;
    }

    /// <summary>Puts the content in an island shaped like the real one, on a backdrop, and writes it at 200%.</summary>
    static void Save(FrameworkElement content, Size island, string path)
    {
        content.HorizontalAlignment = HorizontalAlignment.Left;
        content.VerticalAlignment = VerticalAlignment.Top;
        var clip = new System.Windows.Controls.Grid { ClipToBounds = true };
        clip.Children.Add(content);
        var shape = new System.Windows.Controls.Border
        {
            // The same shape, border and font as IslandWindow.xaml.
            Width = island.Width, Height = island.Height, Background = Brushes.Black,
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF)), BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(28), Child = clip,
        };
        var backdrop = new System.Windows.Controls.Border
        {
            Padding = new Thickness(Backdrop),
            Background = new LinearGradientBrush(Color.FromRgb(0x5E, 0x78, 0xA8), Color.FromRgb(0x24, 0x30, 0x4A), 90),
            Child = shape,
        };
        TextElement.SetFontFamily(backdrop, (FontFamily)Application.Current.FindResource("Poppins"));
        TextElement.SetFontSize(backdrop, 12.5);
        TextElement.SetForeground(backdrop, Brushes.White);

        var size = new Size(island.Width + 2 * Backdrop, island.Height + 2 * Backdrop);
        backdrop.Measure(size);
        backdrop.Arrange(new Rect(size));
        backdrop.UpdateLayout();
        if (content is OpenPanel open) // the selection pill goes where the tabs were just laid out
        {
            open.SettleTabs();
            backdrop.UpdateLayout();
        }
        var bitmap = new RenderTargetBitmap((int)(size.Width * 2), (int)(size.Height * 2), 192, 192, PixelFormats.Pbgra32);
        bitmap.Render(backdrop);
        var png = new PngBitmapEncoder();
        png.Frames.Add(BitmapFrame.Create(bitmap));
        using (var file = File.Create(path)) png.Save(file);

        clip.Children.Clear(); // the same panel goes into the next picture
    }
}
