using System.Windows.Media;

namespace Ledge;

public enum NotificationTone { Neutral, Iris, Mint, Amber }

/// <summary>One readable alert, shared by the live capsule and native previews.</summary>
public sealed record NotificationContent(string Title, string Detail, string Status, string Glyph,
    NotificationTone Tone = NotificationTone.Neutral, Color? Swatch = null, bool Immediate = false)
{
    public string AccessibilityLabel => string.Join(", ", new[] { Title, Detail, Status }.Where(s => !string.IsNullOrWhiteSpace(s)));

    public static NotificationContent Agent(string name, bool waiting, string project)
    {
        var context = project.Trim();
        if (context.Length == 0 || context.All(c => c is '/' or '\\'))
            context = waiting ? "Waiting for your input" : "Task completed";
        return new(name == "Claude" ? "Claude Code" : name, context, waiting ? "Needs you" : "Done",
            "\uE943", waiting ? NotificationTone.Iris : NotificationTone.Mint);
    }

    public static NotificationContent Battery(int percent, bool charging) =>
        new("Battery", charging ? "Power connected" : "Running on battery", $"{Math.Clamp(percent, 0, 100)}%",
            charging ? "\uE945" : "\uE850", charging ? NotificationTone.Mint : percent <= 20 ? NotificationTone.Amber : NotificationTone.Neutral);

    public static NotificationContent Meeting(string title, DateTime startsAt, DateTime now) =>
        new("Meeting soon", title, startsAt <= now ? "Now" : $"{(int)Math.Ceiling((startsAt - now).TotalMinutes)} min",
            "\uE787", NotificationTone.Iris);

    public static NotificationContent Device(bool microphone, string app) =>
        new(microphone ? "Microphone" : "Camera", app, "On", microphone ? "\uE720" : "\uE714",
            microphone ? NotificationTone.Amber : NotificationTone.Mint);

    public static NotificationContent ColorPicked(Color color) =>
        new("Color picked", "Copied to clipboard", ColorPicker.Hex(color), "\uE790", Swatch: color, Immediate: true);

    public static NotificationContent Timer(double minutes) =>
        new("Timer finished", $"{(int)minutes} minute session", "Done", "\uE916", NotificationTone.Mint);

    public static NotificationContent Message(string title, string detail) => new(title, detail, "", "\uE946");
}
