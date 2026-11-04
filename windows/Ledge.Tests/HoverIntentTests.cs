using System.Windows;
using Decision = Ledge.HoverIntent.Decision;

namespace Ledge.Tests;

public class HoverIntentTests
{
    // A closed pill 180 wide, 8 below the top of a screen whose top edge is at 0.
    static readonly Rect Closed = new(870, 8, 180, 32);
    static readonly Rect Open = new(680, 8, 560, 200);

    /// <summary>Feeds pointer samples 16 ms apart and returns the last decision.</summary>
    static Decision Run(HoverIntent hover, Rect island, bool expanded, params Point[] points)
    {
        var decision = Decision.None;
        var time = 0.0;
        foreach (var point in points)
        {
            decision = hover.Update(point, time, island, 0, expanded);
            if (decision != Decision.None) return decision;
            time += 0.016;
        }
        return decision;
    }

    static Point[] Still(Point point, int samples) => Enumerable.Repeat(point, samples).ToArray();

    [Fact]
    public void RestingOverTheIslandOpensIt() =>
        Assert.Equal(Decision.Open, Run(new HoverIntent(), Closed, false, Still(new Point(960, 20), 6)));

    [Fact]
    public void PushingAgainstTheTopEdgeOpensAtOnce() =>
        Assert.Equal(Decision.Open, Run(new HoverIntent(), Closed, false, new Point(960, 0)));

    [Fact]
    public void SweepingPastDoesNotOpen()
    {
        // 40 px every 16 ms is 2500 px/s: on its way somewhere else.
        var sweep = Enumerable.Range(0, 12).Select(i => new Point(800 + i * 40, 20)).ToArray();
        Assert.Equal(Decision.None, Run(new HoverIntent(), Closed, false, sweep));
    }

    [Fact]
    public void FarAwayDoesNothing() =>
        Assert.Equal(Decision.None, Run(new HoverIntent(), Closed, false, Still(new Point(200, 600), 10)));

    [Fact]
    public void RestingBelowTheCompactIslandDoesNotOpenAnAlertUnderThePointer()
    {
        // A notification grows down to y=72, but the compact resting rectangle remains
        // the hover trigger. Its new lower area must not open Home and dismiss the alert.
        Assert.Equal(Decision.None, Run(new HoverIntent(), Closed, false, Still(new Point(960, 64), 30)));
    }

    [Fact]
    public void LeavingDecisivelyClosesAtOnce() =>
        Assert.Equal(Decision.Close, Run(new HoverIntent(), Open, true, new Point(960, 500)));

    [Fact]
    public void SlippingJustPastTheEdgeGetsAMomentsGrace()
    {
        var hover = new HoverIntent();
        var justOutside = new Point(960, Open.Bottom + 30);
        Assert.Equal(Decision.None, hover.Update(justOutside, 0, Open, 0, true));
        Assert.Equal(Decision.None, hover.Update(justOutside, 0.1, Open, 0, true));
        Assert.Equal(Decision.Close, hover.Update(justOutside, 0.2, Open, 0, true));
    }

    [Fact]
    public void ComingBackInsideCancelsTheGrace()
    {
        var hover = new HoverIntent();
        hover.Update(new Point(960, Open.Bottom + 30), 0, Open, 0, true);
        hover.Update(new Point(960, 100), 0.1, Open, 0, true);
        Assert.Equal(Decision.None, hover.Update(new Point(960, Open.Bottom + 30), 0.2, Open, 0, true));
    }

    [Fact]
    public void ThresholdsScaleWithTheDisplay()
    {
        // At 200% the pill is twice as many pixels, and so is the margin around it.
        var hover = new HoverIntent { Scale = 2 };
        var island = new Rect(1740, 16, 360, 64);
        Assert.Equal(Decision.Open, Run(hover, island, false, Still(new Point(1740 - 20, 40), 6)));
    }
}
