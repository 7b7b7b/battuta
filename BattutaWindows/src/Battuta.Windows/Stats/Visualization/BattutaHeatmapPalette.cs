using System.Windows.Media;

namespace Battuta.Windows.Stats.Visualization;

/// <summary>
/// Shared continuous palettes for every statistics heatmap on Windows. The
/// stop locations and RGB values intentionally match the macOS implementation.
/// </summary>
public static class BattutaHeatmapPalette
{
    private static readonly HeatmapColorStop[] SequentialStops =
    [
        new(0.00, Color.FromRgb(0x44, 0x01, 0x54)),
        new(0.13, Color.FromRgb(0x48, 0x24, 0x75)),
        new(0.25, Color.FromRgb(0x41, 0x44, 0x87)),
        new(0.38, Color.FromRgb(0x35, 0x5F, 0x8D)),
        new(0.50, Color.FromRgb(0x21, 0x91, 0x8D)),
        new(0.63, Color.FromRgb(0x22, 0xA8, 0x84)),
        new(0.75, Color.FromRgb(0x44, 0xBF, 0x70)),
        new(0.88, Color.FromRgb(0x7A, 0xD1, 0x51)),
        new(1.00, Color.FromRgb(0xBD, 0xDF, 0x26)),
    ];

    private static readonly HeatmapColorStop[] DivergingStops =
    [
        new(0.00, Color.FromRgb(0x1B, 0x8E, 0xB3)),
        new(0.25, Color.FromRgb(0x2E, 0x63, 0x74)),
        new(0.50, Color.FromRgb(0x3E, 0x42, 0x3E)),
        new(0.75, Color.FromRgb(0x74, 0x9C, 0x38)),
        new(1.00, Color.FromRgb(0xBD, 0xDF, 0x26)),
    ];

    public static Color SequentialColor(double normalizedValue) =>
        Interpolate(normalizedValue, SequentialStops);

    /// <summary>
    /// Maps a signed normalized value in -1...1 through the shared diverging
    /// palette, with zero fixed at its neutral centre color.
    /// </summary>
    public static Color DivergingColor(double normalizedValue) =>
        Interpolate((Math.Clamp(normalizedValue, -1, 1) + 1) / 2, DivergingStops);

    public static LinearGradientBrush CreateSequentialGradientBrush() =>
        CreateGradientBrush(SequentialStops);

    public static LinearGradientBrush CreateDivergingGradientBrush() =>
        CreateGradientBrush(DivergingStops);

    private static LinearGradientBrush CreateGradientBrush(
        IEnumerable<HeatmapColorStop> stops)
    {
        var brush = new LinearGradientBrush
        {
            StartPoint = new System.Windows.Point(0, .5),
            EndPoint = new System.Windows.Point(1, .5),
        };
        foreach (var stop in stops)
        {
            brush.GradientStops.Add(new GradientStop(stop.Color, stop.Location));
        }

        brush.Freeze();
        return brush;
    }

    private static Color Interpolate(
        double rawLocation,
        IReadOnlyList<HeatmapColorStop> stops)
    {
        var location = Math.Clamp(rawLocation, 0, 1);
        if (location <= stops[0].Location)
        {
            return stops[0].Color;
        }

        if (location >= stops[^1].Location)
        {
            return stops[^1].Color;
        }

        for (var index = 1; index < stops.Count; index++)
        {
            var upper = stops[index];
            if (location > upper.Location)
            {
                continue;
            }

            var lower = stops[index - 1];
            var progress = (location - lower.Location) / (upper.Location - lower.Location);
            return Color.FromRgb(
                InterpolateByte(lower.Color.R, upper.Color.R, progress),
                InterpolateByte(lower.Color.G, upper.Color.G, progress),
                InterpolateByte(lower.Color.B, upper.Color.B, progress));
        }

        return stops[^1].Color;
    }

    private static byte InterpolateByte(byte low, byte high, double progress) =>
        (byte)Math.Round(low + (high - low) * Math.Clamp(progress, 0, 1));

    private readonly record struct HeatmapColorStop(double Location, Color Color);
}
