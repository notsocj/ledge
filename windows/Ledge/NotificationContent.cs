using System.Windows.Media;

namespace Ledge;

public enum NotificationTone { Neutral, Iris, Mint, Amber }

/// <summary>One readable alert, shared by the live capsule and native previews.</summary>
public sealed record NotificationContent(string Title, string Detail, string Status, string Glyph,
    NotificationTone Tone = NotificationTone.Neutral, Color? Swatch = null, bool Immediate = false)
{
    public string AccessibilityLabel => string.Join(", ", new[] { Title, Detail, Status }.Where(s => !string.IsNullOrWhiteSpace(s)));
    public string GroupKey { get; init; } = "";
    public NotificationPriority Priority { get; init; } = NotificationPriority.Ambient;
    public double FreshSeconds { get; init; } = 15;
    public DateTimeOffset? ExpiresAt { get; init; }
    public Tool? SourceTool { get; init; }

    public static NotificationContent Agent(string name, bool waiting, string project)
    {
        var projectKey = project.Trim();
        var context = projectKey;
        if (context.Length == 0 || context.All(c => c is '/' or '\\'))
            context = waiting ? "Waiting for your input" : "Task completed";
        return new(name == "Claude" ? "Claude Code" : name, context, waiting ? "Needs you" : "Done",
            "\uE943", waiting ? NotificationTone.Iris : NotificationTone.Mint)
        {
            GroupKey = $"agent:{name}:{projectKey}",
            Priority = waiting ? NotificationPriority.Attention : NotificationPriority.Normal,
            FreshSeconds = waiting ? 30 : 20,
            SourceTool = Tool.AgentAlerts,
        };
    }

    public static NotificationContent Battery(int percent, bool charging) =>
        new("Battery", charging ? "Power connected" : "Running on battery", $"{Math.Clamp(percent, 0, 100)}%",
            charging ? "\uE945" : "\uE850", charging ? NotificationTone.Mint : percent <= 20 ? NotificationTone.Amber : NotificationTone.Neutral)
        {
            GroupKey = "battery", Priority = !charging && percent <= 20 ? NotificationPriority.Normal : NotificationPriority.Ambient,
            FreshSeconds = !charging && percent <= 20 ? 20 : 15,
        };

    public static NotificationContent Meeting(string title, DateTime startsAt, DateTime now) =>
        new("Meeting soon", title, startsAt <= now ? "Now" : $"{(int)Math.Ceiling((startsAt - now).TotalMinutes)} min",
            "\uE787", NotificationTone.Iris)
        {
            GroupKey = $"meeting:{title}:{startsAt.Ticks}", Priority = NotificationPriority.Attention,
            FreshSeconds = 30, ExpiresAt = new DateTimeOffset(startsAt).AddSeconds(30),
            SourceTool = Tool.Calendar,
        };

    public static NotificationContent Device(bool microphone, string app) =>
        new(microphone ? "Microphone" : "Camera", app, "On", microphone ? "\uE720" : "\uE714",
            microphone ? NotificationTone.Amber : NotificationTone.Mint)
        {
            GroupKey = microphone ? "device:microphone" : "device:camera",
            Priority = NotificationPriority.Normal, FreshSeconds = 20,
            SourceTool = Tool.InUse,
        };

    public static NotificationContent ColorPicked(Color color) =>
        new("Color picked", "Copied to clipboard", ColorPicker.Hex(color), "\uE790", Swatch: color, Immediate: true)
        { GroupKey = "color", SourceTool = Tool.ColorPicker };

    public static NotificationContent Timer(double minutes) =>
        new("Timer finished", $"{(int)minutes} minute session", "Done", "\uE916", NotificationTone.Mint)
        {
            GroupKey = "timer", Priority = NotificationPriority.Attention, FreshSeconds = 30,
            SourceTool = Tool.Timer,
        };

    public static NotificationContent Message(string title, string detail) =>
        new(title, detail, "", "\uE946") { GroupKey = $"message:{title}" };
}
