namespace Battuta.Windows.Stats.Visualization;

/// <summary>
/// Maps the non-zero values currently visible in a heatmap onto a stable linear
/// intensity. Small samples use their actual maximum; larger samples cap the
/// high end at P95 so one exceptional value does not wash out the rest of the map.
/// </summary>
public readonly record struct AdaptiveHeatScale(double Low, double High)
{
    private const int PercentileSampleThreshold = 20;
    private const double HighPercentile = .95;

    public bool HasData => High > 0;

    public static AdaptiveHeatScale FromNonZero(IEnumerable<long> values) =>
        FromNonZero(values.Select(value => (double)value));

    public static AdaptiveHeatScale FromNonZero(IEnumerable<double> values)
    {
        ArgumentNullException.ThrowIfNull(values);

        var sorted = values
            .Where(value => double.IsFinite(value) && value > 0)
            .OrderBy(value => value)
            .ToArray();
        if (sorted.Length == 0)
        {
            return default;
        }

        var high = sorted.Length < PercentileSampleThreshold
            ? sorted[^1]
            : Percentile(sorted, HighPercentile);
        return new AdaptiveHeatScale(sorted[0], Math.Max(sorted[0], high));
    }

    /// <summary>
    /// Normalizes a one-direction heatmap from its smallest visible non-zero
    /// value to its adaptive P95 (or maximum for small samples).
    /// </summary>
    public double Normalize(double value)
    {
        if (!HasData || !double.IsFinite(value) || value <= 0)
        {
            return 0;
        }

        if (High <= Low)
        {
            return 1;
        }

        return Math.Clamp((value - Low) / (High - Low), 0, 1);
    }

    /// <summary>
    /// Normalizes the magnitude of a signed heatmap around a neutral zero,
    /// using the same adaptive high bound in both directions.
    /// </summary>
    public double NormalizeMagnitude(double value)
    {
        if (!HasData || !double.IsFinite(value) || value == 0)
        {
            return 0;
        }

        return Math.Clamp(Math.Abs(value) / High, 0, 1);
    }

    private static double Percentile(IReadOnlyList<double> sorted, double fraction)
    {
        var position = Math.Clamp(fraction, 0, 1) * (sorted.Count - 1);
        var lowerIndex = (int)Math.Floor(position);
        var upperIndex = (int)Math.Ceiling(position);
        if (lowerIndex == upperIndex)
        {
            return sorted[lowerIndex];
        }

        var interpolation = position - lowerIndex;
        return sorted[lowerIndex]
            + (sorted[upperIndex] - sorted[lowerIndex]) * interpolation;
    }
}
