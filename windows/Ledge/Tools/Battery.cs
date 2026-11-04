using Forms = System.Windows.Forms;

namespace Ledge;

/// <summary>The battery's charge, with an alert when you plug in or drop to 20% and 10%.</summary>
public sealed class Battery
{
    int? lastPercent;
    bool? wasOnPower;

    /// <summary>Null on PCs without a battery.</summary>
    public int? Percent { get; private set; }
    public bool OnPower { get; private set; }
    public event Action? Changed;
    public event Action<string, string>? Alert;

    public static bool ShouldWarn(int previous, int percent) => new[] { 20, 10 }.Any(level => previous > level && percent <= level);

    /// <summary>For snapshots, which run on PCs without a battery.</summary>
    internal void ShowDemo(int percent, bool onPower)
    {
        (Percent, OnPower) = (percent, onPower);
        Changed?.Invoke();
    }

    public void Check()
    {
        var status = Forms.SystemInformation.PowerStatus;
        // BatteryLifePercent is 0 to 1, or 2.55 when Windows doesn't know.
        if (status.BatteryChargeStatus.HasFlag(Forms.BatteryChargeStatus.NoSystemBattery) || status.BatteryLifePercent > 1)
        {
            Percent = null;
            Changed?.Invoke();
            return;
        }
        var percent = (int)Math.Round(status.BatteryLifePercent * 100);
        var onPower = status.PowerLineStatus == Forms.PowerLineStatus.Online;
        if (onPower && wasOnPower == false) Alert?.Invoke("Charging", $"{percent}%");
        else if (!onPower && lastPercent is { } previous && ShouldWarn(previous, percent)) Alert?.Invoke("Low battery", $"{percent}%");
        (lastPercent, wasOnPower, Percent, OnPower) = (percent, onPower, percent, onPower);
        Changed?.Invoke();
    }
}
