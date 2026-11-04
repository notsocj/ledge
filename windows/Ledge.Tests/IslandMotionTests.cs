using System.Windows;

namespace Ledge.Tests;

public class IslandMotionTests
{
    static readonly Size Compact = new(180, 32), Notification = new(364, 64);

    static void Settle(IslandMotion motion)
    {
        for (var frame = 0; frame < 240 && motion.IsMoving; frame++) motion.Step(1.0 / 60);
        Assert.False(motion.IsMoving);
    }

    [Fact]
    public void NotificationGrowsTheCompactSurfaceAndRestoresItOnDismissal()
    {
        var motion = new IslandMotion(Compact);
        motion.Retarget(Notification, notification: true);
        Assert.Equal(180, motion.Width);
        Assert.Equal(32, motion.Height);
        Assert.Equal(0, motion.NotificationReveal);
        motion.Step(1.0 / 60);
        Assert.InRange(motion.Width, 180.001, 364);
        Assert.InRange(motion.Height, 32.001, 64);
        Settle(motion);
        Assert.Equal(364, motion.Width);
        Assert.Equal(64, motion.Height);
        Assert.Equal(32, motion.CornerRadius);
        Assert.Equal(1, motion.NotificationReveal);
        Assert.Equal(0, motion.Bend);

        motion.Retarget(Compact);
        Settle(motion);
        Assert.Equal(180, motion.Width);
        Assert.Equal(32, motion.Height);
        Assert.Equal(16, motion.CornerRadius);
        Assert.Equal(0, motion.NotificationReveal);
        Assert.Equal(0, motion.Bend);
    }

    [Fact]
    public void NotificationCanRestoreTheWiderMediaOrTimerIsland()
    {
        var resting = new Size(250, 32);
        var motion = new IslandMotion(resting);
        motion.Retarget(Notification, notification: true);
        Settle(motion);
        motion.Retarget(resting);
        Settle(motion);
        Assert.Equal(250, motion.Width);
        Assert.Equal(32, motion.Height);
        Assert.Equal(0, motion.NotificationReveal);
    }

    [Fact]
    public void ReplacementDuringEntryDoesNotRestartTheMorph()
    {
        var motion = new IslandMotion(Compact);
        var uninterrupted = new IslandMotion(Compact);
        motion.Retarget(Notification, notification: true);
        uninterrupted.Retarget(Notification, notification: true);
        for (var frame = 0; frame < 5; frame++)
        {
            motion.Step(1.0 / 60);
            uninterrupted.Step(1.0 / 60);
        }
        var before = (motion.Width, motion.Height, motion.NotificationProgress);
        motion.Retarget(Notification, notification: true);
        Assert.Equal(before, (motion.Width, motion.Height, motion.NotificationProgress));
        motion.Step(1.0 / 60);
        uninterrupted.Step(1.0 / 60);
        Assert.Equal((uninterrupted.Width, uninterrupted.Height, uninterrupted.NotificationProgress),
            (motion.Width, motion.Height, motion.NotificationProgress));
        Settle(motion);
        Assert.Equal(364, motion.Width);
    }

    [Fact]
    public void CompleteEntryKeepsJellyDeformationAndOvershootBounded()
    {
        var motion = new IslandMotion(Compact);
        motion.Retarget(Notification, notification: true);
        var maxWidth = motion.Width;
        var maxBend = motion.Bend;
        for (var frame = 0; frame < 180; frame++)
        {
            motion.Step(1.0 / 60);
            maxWidth = Math.Max(maxWidth, motion.Width);
            maxBend = Math.Max(maxBend, motion.Bend);
            Assert.InRange(motion.Height, 32, 67);
            Assert.InRange(motion.Bend, -3, 8);
            Assert.InRange(motion.NotificationReveal, 0, 1);
        }
        Assert.InRange(maxWidth, 364.001, 380);
        Assert.InRange(maxBend, 6, 8);
        Assert.False(motion.IsMoving);
    }

    [Fact]
    public void NotificationDuringRetractionReversesFromItsCurrentSize()
    {
        var motion = new IslandMotion(Compact);
        motion.Retarget(Notification, notification: true);
        Settle(motion);
        motion.Retarget(Compact);
        for (var frame = 0; frame < 4; frame++) motion.Step(1.0 / 60);
        var before = (motion.Width, motion.Height, motion.NotificationProgress);
        motion.Retarget(Notification, notification: true);
        Assert.Equal(before, (motion.Width, motion.Height, motion.NotificationProgress));
        Settle(motion);
        Assert.Equal(364, motion.Width);
        Assert.Equal(64, motion.Height);
    }

    [Fact]
    public void RapidInterruptionsStayFiniteAndSettleToTheLatestTarget()
    {
        var motion = new IslandMotion(Compact);
        for (var frame = 0; frame < 90; frame++)
        {
            if (frame % 6 == 0) motion.Retarget(Notification, notification: true);
            if (frame % 6 == 3) motion.Retarget(Compact);
            motion.Step(1.0 / 60);
            Assert.InRange(motion.Width, 170, 390);
            Assert.InRange(motion.Height, 29, 70);
            Assert.InRange(motion.Bend, -3, 8);
            Assert.InRange(motion.NotificationReveal, 0, 1);
        }
        motion.Retarget(Compact);
        Settle(motion);
        Assert.Equal(180, motion.Width);
        Assert.Equal(32, motion.Height);
        Assert.False(motion.Step(1.0 / 60));
    }

    [Theory]
    [InlineData(true, false)]
    [InlineData(false, true)]
    public void ReducedMotionAndImmediateFeedbackSnapTheSurface(bool reduced, bool immediate)
    {
        var motion = new IslandMotion(Compact);
        motion.Retarget(Notification, notification: true, reduceMotion: reduced, immediate: immediate);
        Assert.Equal(364, motion.Width);
        Assert.Equal(64, motion.Height);
        Assert.Equal(0, motion.Bend);
        Assert.Equal(1, motion.NotificationReveal);
        Assert.False(motion.IsMoving);
        motion.Retarget(Compact, reduceMotion: reduced, immediate: immediate);
        Assert.Equal(180, motion.Width);
        Assert.Equal(32, motion.Height);
        Assert.Equal(0, motion.NotificationReveal);
        Assert.False(motion.IsMoving);
    }

    [Fact]
    public void OpeningThePanelInterruptsTheNotificationWithoutASecondSurface()
    {
        var motion = new IslandMotion(Compact);
        motion.Retarget(Notification, notification: true);
        for (var frame = 0; frame < 5; frame++) motion.Step(1.0 / 60);
        var before = (motion.Width, motion.Height);
        motion.Retarget(new Size(560, 220));
        Assert.Equal(before, (motion.Width, motion.Height));
        Settle(motion);
        Assert.Equal(560, motion.Width);
        Assert.Equal(220, motion.Height);
        Assert.Equal(28, motion.CornerRadius);
        Assert.Equal(0, motion.Bend);
    }

    [Fact]
    public void LabelsStayHiddenWhileTheShapeIsTooNarrowOrTooShort()
    {
        Assert.Equal(0, new IslandMotion(new Size(230, 64)).NotificationReveal);
        Assert.Equal(0, new IslandMotion(new Size(331, 64)).NotificationReveal);
        Assert.Equal(0, new IslandMotion(new Size(350, 64)).NotificationReveal);
        Assert.Equal(0, new IslandMotion(new Size(364, 56)).NotificationReveal);
        Assert.Equal(0.5, new IslandMotion(new Size(357, 64)).NotificationReveal);
        Assert.Equal(1, new IslandMotion(Notification).NotificationReveal);
    }
}
