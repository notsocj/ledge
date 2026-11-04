using System.Windows;
using System.Windows.Media;

namespace Ledge;

/// <summary>One continuously reshaped shell for compact, notifying and expanded states.</summary>
public sealed class IslandSurface : FrameworkElement
{
    static readonly Pen Edge = new(new SolidColorBrush(Color.FromArgb(0x1A, 255, 255, 255)), 0.5);
    static readonly Pen Highlight = new(new LinearGradientBrush(new GradientStopCollection
    {
        new(Color.FromArgb(0x8C, 255, 255, 255), 0), new(Colors.Transparent, 0.5),
        new(Color.FromArgb(0x1F, 255, 255, 255), 1),
    }, new Point(0, 0), new Point(1, 1)), 1);
    double sheen;
    public Geometry Geometry { get; private set; } = System.Windows.Media.Geometry.Empty;

    public void Update(Size size, double cornerRadius, double bend, double sheen)
    {
        Width = size.Width;
        Height = size.Height;
        this.sheen = Math.Clamp(sheen, 0, 1);
        var w = size.Width;
        var h = size.Height;
        var r = Math.Clamp(cornerRadius, 0, Math.Min(w, h) / 2);
        var shape = new StreamGeometry();
        using (var path = shape.Open())
        {
            path.BeginFigure(new Point(r, 0), true, true);
            path.LineTo(new Point(w - r, 0), true, false);
            path.ArcTo(new Point(w, r), new Size(r, r), 0, false, SweepDirection.Clockwise, true, false);
            path.LineTo(new Point(w, h - r), true, false);
            path.ArcTo(new Point(w - r, h), new Size(r, r), 0, false, SweepDirection.Clockwise, true, false);
            path.BezierTo(new Point(w / 2 + r, h + bend), new Point(w / 2 - r, h + bend), new Point(r, h), true, false);
            path.ArcTo(new Point(0, h - r), new Size(r, r), 0, false, SweepDirection.Clockwise, true, false);
            path.LineTo(new Point(0, r), true, false);
            path.ArcTo(new Point(r, 0), new Size(r, r), 0, false, SweepDirection.Clockwise, true, false);
        }
        shape.Freeze();
        Geometry = shape;
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext drawing)
    {
        drawing.DrawGeometry(Brushes.Black, Edge, Geometry);
        if (sheen <= 0) return;
        drawing.PushOpacity(sheen);
        drawing.DrawGeometry(null, Highlight, Geometry);
        drawing.Pop();
    }
}
