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
}
