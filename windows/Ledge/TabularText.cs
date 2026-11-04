using System.Globalization;
using System.Windows;
using System.Windows.Documents;
using System.Windows.Media;

namespace Ledge;

/// <summary>Text whose digits all take the same width, for numbers that tick, like a countdown.
/// Poppins has no tabular figures (its "1" is much narrower than its "0"), so a TextBlock showing
/// 10:11 then 10:10 would shuffle sideways every second. This draws each digit centred in a cell as
/// wide as the widest digit instead; colons and other characters keep their own width.</summary>
public class TabularText : FrameworkElement
{
    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(nameof(Text), typeof(string), typeof(TabularText),
        new FrameworkPropertyMetadata("", FrameworkPropertyMetadataOptions.AffectsMeasure | FrameworkPropertyMetadataOptions.AffectsRender));

    // The font properties are TextElement's inherited ones, as on TextBlock: this picks up the island's font and color,
    // and changing them re-measures and redraws it.
    public static readonly DependencyProperty FontFamilyProperty = TextElement.FontFamilyProperty.AddOwner(typeof(TabularText));
    public static readonly DependencyProperty FontSizeProperty = TextElement.FontSizeProperty.AddOwner(typeof(TabularText));
    public static readonly DependencyProperty FontWeightProperty = TextElement.FontWeightProperty.AddOwner(typeof(TabularText));
    public static readonly DependencyProperty ForegroundProperty = TextElement.ForegroundProperty.AddOwner(typeof(TabularText));

    public string Text { get => (string)GetValue(TextProperty); set => SetValue(TextProperty, value); }
    public FontFamily FontFamily { get => (FontFamily)GetValue(FontFamilyProperty); set => SetValue(FontFamilyProperty, value); }
    public double FontSize { get => (double)GetValue(FontSizeProperty); set => SetValue(FontSizeProperty, value); }
    public FontWeight FontWeight { get => (FontWeight)GetValue(FontWeightProperty); set => SetValue(FontWeightProperty, value); }
    public Brush Foreground { get => (Brush)GetValue(ForegroundProperty); set => SetValue(ForegroundProperty, value); }

    FormattedText Format(string text) => new(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
        new Typeface(FontFamily, FontStyles.Normal, FontWeight, FontStretches.Normal), FontSize, Foreground, VisualTreeHelper.GetDpi(this).PixelsPerDip);

    /// <summary>The widest digit's width: every digit gets a cell this wide.</summary>
    double DigitWidth() => "0123456789".Max(digit => Format(digit.ToString()).WidthIncludingTrailingWhitespace);

    protected override Size MeasureOverride(Size availableSize)
    {
        var digit = DigitWidth();
        var width = Text.Sum(character => char.IsDigit(character) ? digit : Format(character.ToString()).WidthIncludingTrailingWhitespace);
        return new Size(width, Format("0").Height);
    }

    protected override void OnRender(DrawingContext drawing)
    {
        var digit = DigitWidth();
        var x = 0.0;
        foreach (var character in Text)
        {
            var glyph = Format(character.ToString());
            var cell = char.IsDigit(character) ? digit : glyph.WidthIncludingTrailingWhitespace;
            drawing.DrawText(glyph, new Point(x + (cell - glyph.WidthIncludingTrailingWhitespace) / 2, 0));
            x += cell;
        }
    }
}
