using System.Windows.Media;

namespace Ledge.Tests;

public class NotificationTests
{
    static void Advance(NotificationMotion motion, int frames = 120)
    {
        for (var frame = 0; frame < frames; frame++) motion.Step(1.0 / 60);
    }

    [Fact]
    public void EntranceSettlesWithoutLeavingAnAnimationRunning()
    {
        var motion = new NotificationMotion();
        motion.Show();
        Assert.True(motion.IsPresented);
        Assert.True(motion.IsVisible);
        Assert.Equal(0, motion.Opacity);

        motion.Step(1.0 / 60);
        Assert.InRange(motion.Progress, 0.001, 1);
        Assert.InRange(motion.Opacity, 0.001, 1);
        Advance(motion);

        Assert.Equal(1, motion.Progress);
        Assert.Equal(1, motion.Opacity);
        Assert.False(motion.IsMoving);
        Assert.False(motion.Step(1.0 / 60));
    }

    [Fact]
    public void ReplacingAnAlertDuringEntranceDoesNotRestartItsPresentation()
    {
        var motion = new NotificationMotion();
        motion.Show();
        Advance(motion, 5);
        var progress = motion.Progress;
        var opacity = motion.Opacity;

        motion.Show();

        Assert.Equal(progress, motion.Progress);
        Assert.Equal(opacity, motion.Opacity);
        Advance(motion);
        Assert.Equal(1, motion.Progress);
        Assert.Equal(1, motion.Opacity);
        Assert.True(motion.IsVisible);
    }

    [Fact]
    public void NewAlertDuringExitKeepsItsCurrentPositionAndSurvivesTheOldDismissal()
    {
        var motion = new NotificationMotion();
        motion.Show();
        Advance(motion);
        motion.Dismiss();
        Advance(motion, 3);
        var progress = motion.Progress;
        var opacity = motion.Opacity;
        Assert.InRange(opacity, 0.001, 0.999);

        motion.Show();

        Assert.Equal(progress, motion.Progress);
        Assert.Equal(opacity, motion.Opacity);
        Advance(motion); // well beyond the outgoing alert's original completion time
        Assert.True(motion.IsPresented);
        Assert.True(motion.IsVisible);
        Assert.Equal(1, motion.Progress);
        Assert.Equal(1, motion.Opacity);
        Assert.False(motion.IsMoving);
    }

    [Fact]
    public void DismissingDuringEntranceReleasesThePresentationAfterItsFade()
    {
        var motion = new NotificationMotion();
        motion.Show();
        Advance(motion, 5);
        motion.Dismiss();
        Assert.False(motion.IsPresented);
        Assert.True(motion.IsVisible);

        Advance(motion);

        Assert.False(motion.IsVisible);
        Assert.False(motion.IsMoving);
        Assert.Equal(0, motion.Opacity);
        Assert.Equal(0, motion.Progress);
    }

    [Fact]
    public void RapidShowAndDismissAlwaysSettlesToTheLatestRequest()
    {
        var motion = new NotificationMotion();
        for (var attempt = 0; attempt < 12; attempt++)
        {
            motion.Show();
            Advance(motion, 2);
            motion.Dismiss();
            Advance(motion, 2);
            Assert.True(double.IsFinite(motion.Progress));
            Assert.InRange(motion.Opacity, 0, 1);
        }
        motion.Show();
        Advance(motion);
        Assert.True(motion.IsVisible);
        Assert.Equal(1, motion.Opacity);

        motion.Dismiss();
        Advance(motion);
        Assert.False(motion.IsVisible);
        Assert.False(motion.IsMoving);
    }

    [Fact]
    public void ReducedMotionFadesWithoutStretchingOrSliding()
    {
        var motion = new NotificationMotion();
        motion.Show(reduceMotion: true);
        Assert.Equal(1, motion.SurfaceProgress);
        Advance(motion, 3);
        Assert.Equal(1, motion.SurfaceProgress);
        Assert.InRange(motion.Opacity, 0.001, 0.999);
        Advance(motion);
        Assert.Equal(1, motion.Opacity);

        motion.Dismiss(reduceMotion: true);
        Assert.Equal(1, motion.SurfaceProgress);
        Advance(motion, 3);
        Assert.Equal(1, motion.SurfaceProgress);
        Assert.InRange(motion.Opacity, 0.001, 0.999);
        Advance(motion);
        Assert.False(motion.IsVisible);
        Assert.False(motion.IsMoving);
    }

    [Fact]
    public void ImmediateFeedbackAppearsAndDisappearsWithoutMotion()
    {
        var motion = new NotificationMotion();
        motion.Show(immediate: true);
        Assert.Equal(1, motion.Opacity);
        Assert.Equal(1, motion.SurfaceProgress);
        Assert.True(motion.IsVisible);
        Assert.False(motion.IsMoving);

        motion.Dismiss();

        Assert.Equal(0, motion.Opacity);
        Assert.False(motion.IsVisible);
        Assert.False(motion.IsMoving);
    }

    [Fact]
    public void ReducedMotionCanTakeOverAnAlreadyMovingAlert()
    {
        var motion = new NotificationMotion();
        motion.Show();
        Advance(motion, 4);

        motion.Show(reduceMotion: true);

        Assert.Equal(1, motion.SurfaceProgress);
        Advance(motion);
        Assert.True(motion.IsVisible);
        Assert.Equal(1, motion.Opacity);
        Assert.False(motion.IsMoving);
    }

    [Fact]
    public void DismissingAnAlreadyHiddenAlertDoesNotStartAnAnimation()
    {
        var motion = new NotificationMotion();
        motion.Dismiss();
        Assert.False(motion.IsPresented);
        Assert.False(motion.IsVisible);
        Assert.False(motion.IsMoving);
    }

    [Theory]
    [InlineData("")]
    [InlineData("  \r\n ")]
    [InlineData("/")]
    [InlineData("\\")]
    [InlineData("/\\/")]
    public void AgentWithoutUsefulProjectContextStillExplainsItsStatus(string project)
    {
        var waiting = NotificationContent.Agent("Claude", true, project);
        Assert.Equal("Claude Code", waiting.Title);
        Assert.Equal("Waiting for your input", waiting.Detail);
        Assert.Equal("Needs you", waiting.Status);
        Assert.Equal(NotificationTone.Iris, waiting.Tone);

        var done = NotificationContent.Agent("Codex", false, project);
        Assert.Equal("Codex", done.Title);
        Assert.Equal("Task completed", done.Detail);
        Assert.Equal("Done", done.Status);
        Assert.Equal(NotificationTone.Mint, done.Tone);
    }

    [Fact]
    public void AgentKeepsTheProjectSeparateFromTheTitleAndStatus()
    {
        var content = NotificationContent.Agent("Codex", false, "  ledge  ");
        Assert.Equal("Codex", content.Title);
        Assert.Equal("ledge", content.Detail);
        Assert.Equal("Done", content.Status);
        Assert.Equal("Codex, ledge, Done", content.AccessibilityLabel);
    }

    [Fact]
    public void AccessibilityLabelOmitsEmptyFields()
    {
        Assert.Equal("Test alert", NotificationContent.Message("Test alert", "").AccessibilityLabel);
        Assert.Equal("Test alert, Ledge is running", NotificationContent.Message("Test alert", "Ledge is running").AccessibilityLabel);
    }

    [Theory]
    [InlineData(true, "Microphone", NotificationTone.Amber)]
    [InlineData(false, "Camera", NotificationTone.Mint)]
    public void DeviceAlertsNameTheDeviceAndTheApp(bool microphone, string title, NotificationTone tone)
    {
        var content = NotificationContent.Device(microphone, "Meeting app");
        Assert.Equal(title, content.Title);
        Assert.Equal("Meeting app", content.Detail);
        Assert.Equal("On", content.Status);
        Assert.Equal(tone, content.Tone);
    }

    [Theory]
    [InlineData(54, true, NotificationTone.Mint)]
    [InlineData(20, false, NotificationTone.Amber)]
    [InlineData(10, false, NotificationTone.Amber)]
    [InlineData(54, false, NotificationTone.Neutral)]
    public void BatteryUsesTheStatusForChargeAndToneForUrgency(int percent, bool charging, NotificationTone tone)
    {
        var content = NotificationContent.Battery(percent, charging);
        Assert.Equal("Battery", content.Title);
        Assert.Equal($"{percent}%", content.Status);
        Assert.Equal(charging ? "Power connected" : "Running on battery", content.Detail);
        Assert.Equal(tone, content.Tone);
    }

    [Theory]
    [InlineData(-30, "Now")]
    [InlineData(0, "Now")]
    [InlineData(1, "1 min")]
    [InlineData(60, "1 min")]
    [InlineData(61, "2 min")]
    [InlineData(120, "2 min")]
    public void MeetingRoundsUpUntilItStarts(int seconds, string status)
    {
        var now = new DateTime(2026, 11, 4, 14, 0, 0);
        var content = NotificationContent.Meeting("Design review", now.AddSeconds(seconds), now);
        Assert.Equal("Meeting soon", content.Title);
        Assert.Equal("Design review", content.Detail);
        Assert.Equal(status, content.Status);
        Assert.Equal(NotificationTone.Iris, content.Tone);
    }

    [Fact]
    public void ColorFeedbackRetainsTheSwatchAndIsImmediate()
    {
        var color = Color.FromRgb(0x43, 0x68, 0x9A);
        var content = NotificationContent.ColorPicked(color);
        Assert.Equal("Color picked", content.Title);
        Assert.Equal("Copied to clipboard", content.Detail);
        Assert.Equal("#43689A", content.Status);
        Assert.Equal(color, content.Swatch);
        Assert.True(content.Immediate);
    }
}
