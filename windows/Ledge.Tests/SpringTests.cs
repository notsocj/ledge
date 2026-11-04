namespace Ledge.Tests;

public class SpringTests
{
    static int FramesToSettle(Spring spring)
    {
        var frames = 0;
        while (spring.Step(1.0 / 60) && frames < 600) frames++;
        return frames;
    }

    [Fact]
    public void SettlesExactlyOnTarget()
    {
        var spring = new Spring(180);
        spring.Retarget(560, 0.5, 0.2);
        Assert.True(FramesToSettle(spring) < 120); // well within two seconds
        Assert.Equal(560, spring.Value);
        Assert.True(spring.IsSettled);
    }

    [Fact]
    public void BounceOvershootsAndNoBounceDoesNot()
    {
        double Peak(double bounce)
        {
            var spring = new Spring(0);
            spring.Retarget(100, 0.5, bounce);
            var peak = 0.0;
            while (spring.Step(1.0 / 60)) peak = Math.Max(peak, spring.Value);
            return peak;
        }
        Assert.InRange(Peak(0.2), 100.5, 115);
        Assert.InRange(Peak(0), 0, 100.1); // allow for rounding in the integration
    }

    [Fact]
    public void RetargetingMidFlightKeepsMomentum()
    {
        var spring = new Spring(0);
        spring.Retarget(100, 0.5, 0.2);
        for (var i = 0; i < 6; i++) spring.Step(1.0 / 60);
        var before = spring.Value;
        spring.Retarget(0, 0.3, 0);
        spring.Step(1.0 / 60);
        Assert.True(spring.Value > before); // still carried forward a little before turning around
        FramesToSettle(spring);
        Assert.Equal(0, spring.Value);
    }
}
