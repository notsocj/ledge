using System.Windows.Media;

namespace Ledge.Tests;

public class NotificationQueueTests
{
    sealed class Clock
    {
        public DateTimeOffset Now { get; private set; } = new(2026, 11, 4, 12, 0, 0, TimeSpan.Zero);
        public NotificationQueue Queue { get; }
        public Clock() => Queue = new NotificationQueue(() => Now);
        public void Advance(double seconds)
        {
            Now = Now.AddSeconds(seconds);
            Queue.Tick();
        }
    }

    [Fact]
    public void BatteryCannotEraseAnAgentWaitingForInput()
    {
        var clock = new Clock();
        var waiting = NotificationContent.Agent("Codex", true, "ledge");
        var battery = NotificationContent.Battery(20, false);
        clock.Queue.Enqueue(waiting, 10);
        clock.Advance(1);
        clock.Queue.Enqueue(battery, 3);
        Assert.Equal(waiting, clock.Queue.Current);
        Assert.Equal(1, clock.Queue.PendingCount);
        clock.Advance(9);
        Assert.Equal(battery, clock.Queue.Current);
    }

    [Fact]
    public void AgentCompletionReplacesItsWaitingStateWithoutReplayingIt()
    {
        var clock = new Clock();
        clock.Queue.Enqueue(NotificationContent.Agent("Codex", true, "ledge"), 10);
        clock.Advance(2);
        var done = NotificationContent.Agent("Codex", false, "ledge");
        clock.Queue.Enqueue(done, 6);
        Assert.Equal(done, clock.Queue.Current);
        Assert.Equal(0, clock.Queue.PendingCount);
        clock.Advance(6);
        Assert.Null(clock.Queue.Current);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void ResolvingAnActiveAgentLetsAnotherUrgentAlertTakeItsTurn(bool anotherAgent)
    {
        var clock = new Clock();
        clock.Queue.Enqueue(NotificationContent.Agent("Codex", true, "ledge"), 10);
        var pending = anotherAgent
            ? NotificationContent.Agent("Codex", true, "website")
            : NotificationContent.Meeting("Review", clock.Now.AddMinutes(2).UtcDateTime, clock.Now.UtcDateTime);
        clock.Queue.Enqueue(pending, 8);
        var done = NotificationContent.Agent("Codex", false, "ledge");
        clock.Queue.Enqueue(done, 6);
        Assert.Equal(pending, clock.Queue.Current);
        clock.Advance(8);
        Assert.Equal(done, clock.Queue.Current);
    }

    [Fact]
    public void EqualPriorityAlertsUseArrivalOrder()
    {
        var clock = new Clock();
        var first = NotificationContent.Agent("Codex", true, "first");
        var second = NotificationContent.Agent("Claude", true, "second");
        var timer = NotificationContent.Timer(25);
        clock.Queue.Enqueue(first, 2);
        clock.Queue.Enqueue(second, 2);
        clock.Queue.Enqueue(timer, 2);
        clock.Advance(2);
        Assert.Equal(second, clock.Queue.Current);
        clock.Advance(2);
        Assert.Equal(timer, clock.Queue.Current);
    }

    [Fact]
    public void ExactDuplicateDoesNotExtendOrRestartAnActiveAlert()
    {
        var clock = new Clock();
        var alert = NotificationContent.Agent("Codex", true, "ledge");
        clock.Queue.Enqueue(alert, 10);
        var presentation = clock.Queue.CurrentId;
        clock.Advance(7);
        clock.Queue.Enqueue(alert, 10);
        Assert.Equal(presentation, clock.Queue.CurrentId);
        Assert.Equal(TimeSpan.FromSeconds(3), clock.Queue.TimeUntilNextChange);
        clock.Advance(3);
        Assert.Null(clock.Queue.Current);
        clock.Queue.Enqueue(alert, 10);
        Assert.Null(clock.Queue.Current);
        clock.Advance(20);
        clock.Queue.Enqueue(alert, 10);
        Assert.Equal(alert, clock.Queue.Current);
    }

    [Fact]
    public void DeferredDuplicatesDoNotRenewTheirFreshness()
    {
        var clock = new Clock();
        clock.Queue.SetAvailable(false);
        var battery = NotificationContent.Battery(54, true);
        clock.Queue.Enqueue(battery, 3);
        clock.Advance(14);
        clock.Queue.Enqueue(battery, 3);
        clock.Advance(1);
        clock.Queue.SetAvailable(true);
        Assert.Null(clock.Queue.Current);
        Assert.Equal(0, clock.Queue.PendingCount);
    }

    [Fact]
    public void DeferredStatesCoalesceToTheNewestBatteryValue()
    {
        var clock = new Clock();
        clock.Queue.SetAvailable(false);
        clock.Queue.Enqueue(NotificationContent.Battery(54, true), 3);
        clock.Advance(1);
        var updated = NotificationContent.Battery(55, true);
        clock.Queue.Enqueue(updated, 3);
        Assert.Equal(1, clock.Queue.PendingCount);
        clock.Queue.SetAvailable(true);
        Assert.Equal(updated, clock.Queue.Current);
    }

    [Fact]
    public void HomeOrFullscreenHoldsFreshAlertsButDoesNotReplayExpiredOnes()
    {
        var clock = new Clock();
        clock.Queue.SetAvailable(false);
        var waiting = NotificationContent.Agent("Codex", true, "ledge");
        clock.Queue.Enqueue(waiting, 10);
        clock.Advance(5);
        Assert.Null(clock.Queue.Current);
        clock.Queue.SetAvailable(true);
        Assert.Equal(waiting, clock.Queue.Current);

        clock.Queue.SetAvailable(false);
        clock.Advance(25);
        clock.Queue.SetAvailable(true);
        Assert.Null(clock.Queue.Current);
        Assert.Equal(0, clock.Queue.PendingCount);
    }

    [Fact]
    public void SuppressionPreservesOnlyTheRemainingVisibleTime()
    {
        var clock = new Clock();
        var waiting = NotificationContent.Agent("Codex", true, "ledge");
        clock.Queue.Enqueue(waiting, 10);
        clock.Advance(3);
        clock.Queue.SetAvailable(false);
        clock.Advance(4);
        clock.Queue.SetAvailable(true);
        Assert.Equal(waiting, clock.Queue.Current);
        Assert.Equal(TimeSpan.FromSeconds(7), clock.Queue.TimeUntilNextChange);
        clock.Advance(7);
        Assert.Null(clock.Queue.Current);
    }

    [Fact]
    public void ImmediateFeedbackInterruptsThenRestoresTheUnreadAlert()
    {
        var clock = new Clock();
        var waiting = NotificationContent.Agent("Codex", true, "ledge");
        clock.Queue.Enqueue(waiting, 10);
        clock.Advance(3);
        var color = NotificationContent.ColorPicked(Colors.Coral);
        clock.Queue.Enqueue(color, 2);
        Assert.Equal(color, clock.Queue.Current);
        clock.Advance(2);
        Assert.Equal(waiting, clock.Queue.Current);
        Assert.Equal(TimeSpan.FromSeconds(7), clock.Queue.TimeUntilNextChange);
        clock.Advance(7);
        Assert.Null(clock.Queue.Current);
    }

    [Fact]
    public void ImmediateFeedbackNeverWaitsBehindHomeOrFullscreen()
    {
        var clock = new Clock();
        clock.Queue.SetAvailable(false);
        clock.Queue.Enqueue(NotificationContent.ColorPicked(Colors.Coral), 2);
        Assert.Equal(0, clock.Queue.PendingCount);
        clock.Queue.SetAvailable(true);
        Assert.Null(clock.Queue.Current);
    }

    [Fact]
    public void RepeatedImmediateFeedbackStillRespondsToEachInput()
    {
        var clock = new Clock();
        var color = NotificationContent.ColorPicked(Colors.Coral);
        clock.Queue.Enqueue(color, 2);
        var first = clock.Queue.CurrentId;
        clock.Advance(1);
        clock.Queue.Enqueue(color, 2);
        Assert.NotEqual(first, clock.Queue.CurrentId);
        Assert.Equal(TimeSpan.FromSeconds(2), clock.Queue.TimeUntilNextChange);
        Assert.Equal(0, clock.Queue.PendingCount);
    }

    [Fact]
    public void PendingQueueIsBoundedAndKeepsUrgentAlertsDuringABurst()
    {
        var clock = new Clock();
        clock.Queue.SetAvailable(false);
        var waiting = NotificationContent.Agent("Codex", true, "ledge");
        clock.Queue.Enqueue(waiting, 1);
        for (var index = 0; index < 10; index++)
            clock.Queue.Enqueue(NotificationContent.Message($"Source {index}", "Done"), 1);
        Assert.Equal(4, clock.Queue.PendingCount);
        clock.Queue.SetAvailable(true);
        Assert.Equal(waiting, clock.Queue.Current);
        clock.Advance(1);
        Assert.Equal("Source 7", clock.Queue.Current?.Title);
    }

    [Fact]
    public void MeetingExpiresShortlyAfterItsStartEvenIfItWasNeverShown()
    {
        var clock = new Clock();
        clock.Queue.SetAvailable(false);
        var meeting = NotificationContent.Meeting("Review", clock.Now.AddSeconds(-20).UtcDateTime, clock.Now.UtcDateTime);
        clock.Queue.Enqueue(meeting, 8);
        clock.Advance(10);
        clock.Queue.SetAvailable(true);
        Assert.Null(clock.Queue.Current);
        Assert.Equal(0, clock.Queue.PendingCount);
    }

    [Fact]
    public void HigherPriorityPreemptionCannotExtendAnOldAlertsExpiry()
    {
        var clock = new Clock();
        var battery = NotificationContent.Battery(54, true);
        clock.Queue.Enqueue(battery, 3);
        clock.Advance(1);
        clock.Queue.Enqueue(NotificationContent.Agent("Codex", true, "ledge"), 20);
        clock.Advance(20);
        Assert.Null(clock.Queue.Current);
        Assert.Equal(0, clock.Queue.PendingCount);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    public void InvalidDurationCannotCreateANeverEndingNotification(double duration)
    {
        var queue = new NotificationQueue();
        queue.Enqueue(NotificationContent.Message("Test", ""), duration);
        Assert.Null(queue.Current);
        Assert.Null(queue.TimeUntilNextChange);
    }

    [Fact]
    public void DisablingAToolRemovesItsDeferredAlertsButKeepsOtherSources()
    {
        var clock = new Clock();
        clock.Queue.SetAvailable(false);
        var waiting = NotificationContent.Agent("Codex", true, "ledge");
        var battery = NotificationContent.Battery(54, true);
        clock.Queue.Enqueue(waiting, 10);
        clock.Queue.Enqueue(battery, 3);
        clock.Queue.RemoveWhere(content => content.SourceTool == Tool.AgentAlerts);
        Assert.Equal(1, clock.Queue.PendingCount);
        clock.Queue.SetAvailable(true);
        Assert.Equal(battery, clock.Queue.Current);
        // Re-enabling a source permits a genuinely new hook, even when its content is unchanged.
        clock.Queue.Enqueue(waiting, 10);
        Assert.Equal(waiting, clock.Queue.Current);
    }
}
