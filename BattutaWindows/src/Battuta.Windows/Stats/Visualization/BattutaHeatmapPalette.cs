using System.Windows.Media;

namespace Battuta.Windows.Stats.Visualization;

/// <summary>
/// View-specific heatmap mappings based on Battuta's original green and cyan
/// statistics styling. Alpha is part of each stop so the ramps retain the
/// layered appearance of the 1.1.1 heatmaps on dark cards.
/// </summary>
public static class BattutaHeatmapPalette
{
    private static readonly HeatmapColorStop[] KeyboardFillStops =
    [
        new(0.00, Color.FromArgb(0x19, 0xB8, 0xE8, 0x4D)),
        new(1.00, Color.FromArgb(0x8E, 0xB8, 0xE8, 0x4D)),
    ];

    private static readonly HeatmapColorStop[] KeyboardLegendStops =
    [
        new(0.00, Color.FromArgb(0x1A, 0xB8, 0xE8, 0x4D)),
        new(0.33, Color.FromArgb(0x40, 0xB8, 0xE8, 0x4D)),
        new(0.67, Color.FromArgb(0x66, 0xB8, 0xE8, 0x4D)),
        new(1.00, Color.FromArgb(0x8F, 0xB8, 0xE8, 0x4D)),
    ];

    private static readonly HeatmapColorStop[] KeyboardBorderStops =
    [
        new(0.00, Color.FromArgb(0x42, 0xB8, 0xE8, 0x4D)),
        new(1.00, Color.FromArgb(0x99, 0xB8, 0xE8, 0x4D)),
    ];

    private static readonly HeatmapColorStop[] ApplicationTimelineStops =
    [
        new(0.00, Color.FromArgb(0x48, 0x40, 0xB8, 0xD1)),
        new(0.33, Color.FromArgb(0x8C, 0x40, 0xB8, 0xD1)),
        new(0.67, Color.FromArgb(0xB8, 0xB8, 0xE8, 0x4D)),
        new(1.00, Color.FromArgb(0xFF, 0x91, 0xC9, 0x2B)),
    ];

    private static readonly HeatmapColorStop[] RhythmCurrentStops =
    [
        new(0.00, Color.FromArgb(0x28, 0xB8, 0xE8, 0x4D)),
        new(1.00, Color.FromArgb(0xC1, 0xB8, 0xE8, 0x4D)),
    ];

    private static readonly HeatmapColorStop[] RhythmIncreaseStops =
    [
        new(0.00, Color.FromArgb(0x23, 0xB8, 0xE8, 0x4D)),
        new(1.00, Color.FromArgb(0xC1, 0xB8, 0xE8, 0x4D)),
    ];

    private static readonly HeatmapColorStop[] RhythmDecreaseStops =
    [
        new(0.00, Color.FromArgb(0x23, 0x40, 0xB8, 0xD1)),
        new(1.00, Color.FromArgb(0xB7, 0x40, 0xB8, 0xD1)),
    ];

    private static readonly HeatmapColorStop[] RhythmDifferenceGradientStops =
    [
        new(0.00, Color.FromArgb(0xB7, 0x40, 0xB8, 0xD1)),
        new(0.45, Color.FromArgb(0x23, 0x40, 0xB8, 0xD1)),
        new(0.50, Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF)),
        new(0.55, Color.FromArgb(0x23, 0xB8, 0xE8, 0x4D)),
        new(1.00, Color.FromArgb(0xC1, 0xB8, 0xE8, 0x4D)),
    ];

    private static readonly HeatmapColorStop[] YearStops =
    [
        new(0.00, Color.FromArgb(0x3D, 0xB8, 0xE8, 0x4D)),
        new(0.33, Color.FromArgb(0x6B, 0xB8, 0xE8, 0x4D)),
        new(0.67, Color.FromArgb(0xA8, 0xB8, 0xE8, 0x4D)),
        new(1.00, Color.FromArgb(0xEB, 0xB8, 0xE8, 0x4D)),
    ];

    public static Color KeyboardFillColor(double normalizedValue) =>
        Interpolate(normalizedValue, KeyboardFillStops);

    public static Color KeyboardBorderColor(double normalizedValue) =>
        Interpolate(normalizedValue, KeyboardBorderStops);

    public static Color ApplicationTimelineColor(double normalizedValue)
    {
        var value = Math.Clamp(normalizedValue, 0, 1);
        if (value < .25)
        {
            return ApplicationTimelineStops[0].Color;
        }

        if (value < .55)
        {
            return ApplicationTimelineStops[1].Color;
        }

        return value < .82
            ? ApplicationTimelineStops[2].Color
            : ApplicationTimelineStops[3].Color;
    }

    public static Color RhythmCurrentColor(double normalizedValue) =>
        Interpolate(normalizedValue, RhythmCurrentStops);

    public static Color RhythmIncreaseColor(double normalizedMagnitude) =>
        Interpolate(normalizedMagnitude, RhythmIncreaseStops);

    public static Color RhythmDecreaseColor(double normalizedMagnitude) =>
        Interpolate(normalizedMagnitude, RhythmDecreaseStops);

    /// <summary>
    /// Maps a signed normalized value in -1...1 to the cyan decrease or green
    /// increase ramp. Zero remains the original translucent neutral cell.
    /// </summary>
    public static Color RhythmDifferenceColor(double normalizedValue)
    {
        var value = Math.Clamp(normalizedValue, -1, 1);
        if (value < 0)
        {
            return RhythmDecreaseColor(-value);
        }

        return value > 0
            ? RhythmIncreaseColor(value)
            : Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF);
    }

    public static Color YearColor(double normalizedValue) =>
        Interpolate(normalizedValue, YearStops);

    public static LinearGradientBrush CreateKeyboardGradientBrush() =>
        CreateGradientBrush(KeyboardLegendStops);

    public static LinearGradientBrush CreateApplicationTimelineGradientBrush() =>
        CreateGradientBrush(ApplicationTimelineStops);

    public static LinearGradientBrush CreateRhythmCurrentGradientBrush() =>
        CreateGradientBrush(RhythmCurrentStops);

    public static LinearGradientBrush CreateRhythmDifferenceGradientBrush() =>
        CreateGradientBrush(RhythmDifferenceGradientStops);

    public static LinearGradientBrush CreateYearGradientBrush() =>
        CreateGradientBrush(YearStops);

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
            return Color.FromArgb(
                InterpolateByte(lower.Color.A, upper.Color.A, progress),
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
