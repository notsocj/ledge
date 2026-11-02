namespace Ledge.Tests;

public class CountdownTests
{
    DateTime now = new(2026, 11, 3, 9, 0, 0, DateTimeKind.Utc);
    Countdown Make() => new(() => now);

    [Fact]
    public void CountsDownAndFinishesOnce()
    {
        var countdown = Make();
        countdown.Start(5);
        Assert.Equal("5:00", Countdown.Format(countdown.Remaining));
        now = now.AddMinutes(2).AddSeconds(30);
        Assert.Equal("2:30", Countdown.Format(countdown.Remaining));
        Assert.False(countdown.Tick());
        now = now.AddMinutes(3);
        Assert.True(countdown.Tick());
        Assert.False(countdown.Tick());
        Assert.False(countdown.IsActive);
    }

    [Fact]
    public void PausingFreezesTheTimeLeft()
    {
        var countdown = Make();
        countdown.Start(5);
        now = now.AddMinutes(1);
        countdown.Pause();
        now = now.AddMinutes(10);
        Assert.Equal(TimeSpan.FromMinutes(4), countdown.Remaining);
        Assert.False(countdown.Tick());
        countdown.Resume();
        now = now.AddMinutes(4);
        Assert.True(countdown.Tick());
    }

    [Fact]
    public void AddingAMinuteWorksRunningOrPaused()
    {
        var countdown = Make();
        countdown.Start(1);
        countdown.AddMinute();
        Assert.Equal(TimeSpan.FromMinutes(2), countdown.Remaining);
        countdown.Pause();
        countdown.AddMinute();
        Assert.Equal(TimeSpan.FromMinutes(3), countdown.Remaining);
        Assert.Equal(TimeSpan.FromMinutes(3), countdown.Total);
    }

    [Theory]
    [InlineData(1500, "25:00")]
    [InlineData(1499.2, "25:00")] // rounds up: a fresh timer never shows a second less than you asked for
    [InlineData(245, "4:05")]
    [InlineData(3723, "1:02:03")]
    [InlineData(0, "0:00")]
    public void Formats(double seconds, string expected) =>
        Assert.Equal(expected, Countdown.Format(TimeSpan.FromSeconds(seconds)));
}

public class BatteryTests
{
    [Theory]
    [InlineData(21, 20, true)]
    [InlineData(11, 10, true)]
    [InlineData(25, 9, true)] // dropped past both while asleep: still one warning
    [InlineData(20, 19, false)] // already warned at 20
    [InlineData(50, 40, false)]
    [InlineData(10, 12, false)] // charging back up
    public void WarnsCrossing20And10(int previous, int percent, bool warns) =>
        Assert.Equal(warns, Battery.ShouldWarn(previous, percent));
}

public class PortsTests
{
    const string Windows = @"C:\Windows";

    [Fact]
    public void ReadsNetworkByteOrder()
    {
        Assert.Equal(3000, Ports.NetworkPort(0xB80B)); // 3000 is 0x0BB8, stored as bytes 0B B8
        Assert.Equal(5173, Ports.NetworkPort(0x3514));
    }

    [Theory]
    [InlineData(3000, @"C:\Program Files\nodejs\node.exe", true)]
    [InlineData(5173, @"C:\Users\cj\AppData\Local\bun\bun.exe", true)]
    [InlineData(135, @"C:\Windows\System32\svchost.exe", false)]
    [InlineData(445, @"c:\windows\system32\ntoskrnl.exe", false)] // paths can come back in any case
    [InlineData(5000, @"C:\WindowsApps\thing.exe", true)] // only the Windows folder itself, not names that start with it
    [InlineData(55000, @"C:\Program Files\nodejs\node.exe", false)] // short-lived port range
    [InlineData(8080, null, false)] // couldn't look at the process: not yours
    public void ShowsOnlyYourOwnServers(int port, string? path, bool shown) =>
        Assert.Equal(shown, Ports.IsYours(port, path, Windows));
}
