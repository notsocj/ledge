using System.Windows.Threading;

namespace Ledge;

/// <summary>The tools behind the island, shared by the closed island and the open panel.</summary>
public sealed class Tools(Dispatcher dispatcher)
{
    public NowPlaying NowPlaying { get; } = new(dispatcher);
    public Battery Battery { get; } = new();
    public KeepAwake KeepAwake { get; } = new();
    public Countdown Countdown { get; } = new(() => DateTime.UtcNow);
    public AgentAlerts Agents { get; } = new();
    public ClipboardHistory Clipboard { get; } = new();
    public Shelf Shelf { get; } = new();
    public ColorPicker ColorPicker { get; } = new();
    public InUse InUse { get; } = new();
    public CalendarFeed Calendar { get; } = new();
    public F1Feed F1 { get; } = new();
}
