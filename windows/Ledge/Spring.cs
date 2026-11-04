namespace Ledge;

/// <summary>
/// A damped spring driven frame by frame, set up like SwiftUI's spring(duration:bounce:) so the
/// island moves the way it does on the Mac. Changing the target keeps the current velocity, so an
/// island that's closed mid-opening turns around smoothly instead of restarting.
/// </summary>
public sealed class Spring(double value)
{
    double stiffness, damping;

    public double Value { get; private set; } = value;
    public double Velocity { get; private set; }
    public double Target { get; private set; } = value;
    public bool IsSettled => Value == Target && Velocity == 0;

    /// <summary>Heads for a new target with the given feel. Bounce 0 settles without overshoot.</summary>
    public void Retarget(double target, double duration, double bounce)
    {
        Target = target;
        stiffness = Math.Pow(2 * Math.PI / duration, 2);
        damping = 4 * Math.PI * (1 - bounce) / duration;
    }

    /// <summary>Jumps straight to a value, for reduced motion and first layout.</summary>
    public void Snap(double value)
    {
        Value = Target = value;
        Velocity = 0;
    }

    /// <summary>Advances by <paramref name="seconds"/>. Returns false once it has come to rest.</summary>
    public bool Step(double seconds)
    {
        if (IsSettled) return false;
        // Small fixed substeps keep the integration stable even when a frame arrives late.
        for (var left = Math.Min(seconds, 0.1); left > 0; left -= 1.0 / 240)
        {
            var dt = Math.Min(left, 1.0 / 240);
            Velocity += (stiffness * (Target - Value) - damping * Velocity) * dt;
            Value += Velocity * dt;
        }
        if (Math.Abs(Target - Value) < 0.01 && Math.Abs(Velocity) < 0.5) Snap(Target);
        return !IsSettled;
    }
}
