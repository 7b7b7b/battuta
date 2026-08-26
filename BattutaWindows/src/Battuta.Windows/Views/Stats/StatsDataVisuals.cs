using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Input;
using System.Windows.Media;
using Battuta.Windows.Stats.Models;
using Battuta.Windows.Stats.Visualization;

namespace Battuta.Windows.Views.Stats;

public enum StatsRhythmMode
{
    Current,
    Difference,
}

public readonly record struct StatsHeatmapGeometry(
    double AxisWidth,
    double Gap,
    double CellSize,
    int ColumnCount,
    double GridWidth,
    double RequiredHeight,
    Rect LegendBounds)
{
    public double RightRemainder(double availableWidth) =>
        Math.Max(0, availableWidth - GridWidth);
}

public static class StatsVisualizationMath
{
    public static double[] Smooth(IReadOnlyList<long> values)
    {
        ReadOnlySpan<double> weights = [1, 2, 3, 2, 1];
        var output = new double[values.Count];
        for (var index = 0; index < values.Count; index++)
        {
            var total = 0d;
            var weightTotal = 0d;
            for (var offset = -2; offset <= 2; offset++)
            {
                var neighbor = index + offset;
                if (neighbor < 0 || neighbor >= values.Count)
                {
                    continue;
                }

                var weight = weights[offset + 2];
                total += values[neighbor] * weight;
                weightTotal += weight;
            }

            output[index] = weightTotal > 0 ? total / weightTotal : 0;
        }

        return output;
    }

    public static double SignificantDifference(double current, double comparison)
    {
        var difference = current - comparison;
        var tolerance = Math.Max(2, Math.Max(current, comparison) * .05);
        return Math.Abs(difference) <= tolerance ? 0 : difference;
    }

    public static IReadOnlyDictionary<int, int> WeekdayOccurrences(TypingDateRange range)
    {
        var result = Enumerable.Range(1, 7).ToDictionary(value => value, _ => 0);
        for (var date = range.StartDate; date <= range.EndDate; date = date.AddDays(1))
        {
            var weekday = (int)date.DayOfWeek + 1;
            result[weekday]++;
        }

        return result;
    }
}

public sealed class StatsTrendChart : FrameworkElement
{
    public static readonly DependencyProperty BucketsProperty = DependencyProperty.Register(
        nameof(Buckets),
        typeof(IReadOnlyList<TypingBucket>),
        typeof(StatsTrendChart),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty RangeProperty = DependencyProperty.Register(
        nameof(Range),
        typeof(TypingTimelineRange),
        typeof(StatsTrendChart),
        new FrameworkPropertyMetadata(TypingTimelineRange.OneHour, FrameworkPropertyMetadataOptions.AffectsRender));

    public StatsTrendChart()
    {
        AutomationProperties.SetName(this, "输入趋势图");
        IsHitTestVisible = false;
    }

    public IReadOnlyList<TypingBucket>? Buckets
    {
        get => (IReadOnlyList<TypingBucket>?)GetValue(BucketsProperty);
        set => SetValue(BucketsProperty, value);
    }

    public TypingTimelineRange Range
    {
        get => (TypingTimelineRange)GetValue(RangeProperty);
        set => SetValue(RangeProperty, value);
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        if (ActualWidth < 40 || ActualHeight < 24)
        {
            return;
        }

        var chart = new Rect(30, 6, Math.Max(1, ActualWidth - 36), Math.Max(1, ActualHeight - 24));
        var gridPen = FrozenPen(Color.FromArgb(22, 255, 255, 255), 1);
        for (var index = 0; index <= 3; index++)
        {
            var y = chart.Top + chart.Height * index / 3;
            drawingContext.DrawLine(gridPen, new Point(chart.Left, y), new Point(chart.Right, y));
        }

        var buckets = Buckets;
        if (buckets is not { Count: > 0 } || buckets.All(bucket => bucket.CharacterCount == 0))
        {
            return;
        }

        var raw = buckets.Select(bucket => bucket.CharacterCount).ToArray();
        var smooth = StatsVisualizationMath.Smooth(raw);
        var maximum = Math.Max(1, Math.Max(raw.Max(), smooth.Max()));
        var step = chart.Width / Math.Max(1, raw.Length - 1);
        var barBrush = FrozenBrush(Color.FromArgb(28, 184, 232, 77));
        var points = new Point[smooth.Length];
        for (var index = 0; index < raw.Length; index++)
        {
            var x = chart.Left + index * step;
            var rawY = chart.Bottom - raw[index] / maximum * chart.Height * .92;
            var width = Math.Max(1, step * .64);
            drawingContext.DrawRoundedRectangle(
                barBrush,
                null,
                new Rect(x - width / 2, rawY, width, chart.Bottom - rawY),
                1.5,
                1.5);
            points[index] = new Point(
                x,
                chart.Bottom - smooth[index] / maximum * chart.Height * .92);
        }

        var area = new StreamGeometry();
        using (var context = area.Open())
        {
            context.BeginFigure(new Point(points[0].X, chart.Bottom), true, true);
            context.LineTo(points[0], true, false);
            for (var index = 1; index < points.Length; index++)
            {
                context.LineTo(points[index], true, false);
            }

            context.LineTo(new Point(points[^1].X, chart.Bottom), true, false);
        }

        area.Freeze();
        var areaBrush = new LinearGradientBrush(
            Color.FromArgb(56, 184, 232, 77),
            Color.FromArgb(2, 184, 232, 77),
            90);
        areaBrush.Freeze();
        drawingContext.DrawGeometry(areaBrush, null, area);

        var line = new StreamGeometry();
        using (var context = line.Open())
        {
            context.BeginFigure(points[0], false, false);
            for (var index = 1; index < points.Length; index++)
            {
                context.LineTo(points[index], true, false);
            }
        }

        line.Freeze();
        var linePen = FrozenPen(Color.FromRgb(145, 201, 43), 2.6);
        linePen.StartLineCap = PenLineCap.Round;
        linePen.EndLineCap = PenLineCap.Round;
        linePen.LineJoin = PenLineJoin.Round;
        drawingContext.DrawGeometry(null, linePen, line);

        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        DrawAxisLabel(drawingContext, AxisLabel(buckets[0].Start), new Point(chart.Left, chart.Bottom + 3), dpi, TextAlignment.Left);
        DrawAxisLabel(
            drawingContext,
            AxisLabel(buckets[buckets.Count / 2].Start),
            new Point(chart.Left + chart.Width / 2, chart.Bottom + 3),
            dpi,
            TextAlignment.Center);
        DrawAxisLabel(
            drawingContext,
            AxisLabel(buckets[^1].Start.AddSeconds(Range.GetDefinition().BucketSeconds)),
            new Point(chart.Right, chart.Bottom + 3),
            dpi,
            TextAlignment.Right);
    }

    private string AxisLabel(DateTimeOffset value) => Range switch
    {
        TypingTimelineRange.SevenDays => value.ToLocalTime().ToString("MM-dd", CultureInfo.CurrentCulture),
        TypingTimelineRange.TwentyFourHours => value.ToLocalTime().ToString("HH", CultureInfo.CurrentCulture),
        _ => value.ToLocalTime().ToString("HH:mm", CultureInfo.CurrentCulture),
    };

    private static void DrawAxisLabel(
        DrawingContext drawingContext,
        string value,
        Point point,
        double dpi,
        TextAlignment alignment)
    {
        var text = new FormattedText(
            value,
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            new Typeface("Segoe UI Variable"),
            8,
            FrozenBrush(Color.FromArgb(130, 255, 255, 255)),
            dpi)
        {
            TextAlignment = alignment,
        };
        drawingContext.DrawText(text, point);
    }

    private static SolidColorBrush FrozenBrush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private static Pen FrozenPen(Color color, double width)
    {
        var pen = new Pen(FrozenBrush(color), width);
        return pen;
    }
}

public sealed class StatsAppTimeline : FrameworkElement
{
    public static readonly DependencyProperty TimelinesProperty = DependencyProperty.Register(
        nameof(Timelines),
        typeof(IReadOnlyList<TypingAppTimeline>),
        typeof(StatsAppTimeline),
            new FrameworkPropertyMetadata(
            null,
            FrameworkPropertyMetadataOptions.AffectsRender | FrameworkPropertyMetadataOptions.AffectsMeasure));

    public static readonly DependencyProperty RangeProperty = DependencyProperty.Register(
        nameof(Range),
        typeof(TypingTimelineRange),
        typeof(StatsAppTimeline),
        new FrameworkPropertyMetadata(TypingTimelineRange.OneHour, FrameworkPropertyMetadataOptions.AffectsRender));

    public StatsAppTimeline()
    {
        AutomationProperties.SetName(this, "应用输入时间线");
        IsHitTestVisible = false;
    }

    public IReadOnlyList<TypingAppTimeline>? Timelines
    {
        get => (IReadOnlyList<TypingAppTimeline>?)GetValue(TimelinesProperty);
        set => SetValue(TimelinesProperty, value);
    }

    public TypingTimelineRange Range
    {
        get => (TypingTimelineRange)GetValue(RangeProperty);
        set => SetValue(RangeProperty, value);
    }

    protected override Size MeasureOverride(Size availableSize)
    {
        var count = Math.Min(20, Timelines?.Count ?? 0);
        var width = double.IsInfinity(availableSize.Width) ? 880 : availableSize.Width;
        return new Size(width, Math.Max(0, count * 33d + (count > 0 ? 18 : 0)));
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        if (Timelines is not { Count: > 0 } timelines)
        {
            return;
        }

        const double appWidth = 150;
        const double countWidth = 74;
        const double gap = 12;
        var timelineX = appWidth + countWidth + gap * 2;
        var timelineWidth = Math.Max(1, ActualWidth - timelineX);
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var rows = timelines.Take(20).ToArray();
        var bucketCount = Math.Max(1, rows.Max(row => row.Buckets.Count));
        var heatScale = AdaptiveHeatScale.FromNonZero(
            rows.SelectMany(row => row.Buckets).Select(bucket => bucket.CharacterCount));

        for (var rowIndex = 0; rowIndex < rows.Length; rowIndex++)
        {
            var row = rows[rowIndex];
            var y = rowIndex * 33d;
            DrawText(drawingContext, row.Application.DisplayName, new Point(0, y + 6), 11, dpi, false);
            DrawText(
                drawingContext,
                row.RangeCharacterCount.ToString("N0", CultureInfo.CurrentCulture),
                new Point(appWidth + 12, y + 6),
                11,
                dpi,
                true);
            for (var bucketIndex = 0; bucketIndex < bucketCount; bucketIndex++)
            {
                var value = bucketIndex < row.Buckets.Count
                    ? row.Buckets[bucketIndex].CharacterCount
                    : 0;
                var intensity = heatScale.Normalize(value);
                var color = value <= 0
                    ? Color.FromArgb(14, 255, 255, 255)
                    : BattutaHeatmapPalette.ApplicationTimelineColor(intensity);
                var width = Math.Max(1, timelineWidth / bucketCount - 1);
                drawingContext.DrawRoundedRectangle(
                    FrozenBrush(color),
                    null,
                    new Rect(
                        timelineX + bucketIndex * timelineWidth / bucketCount,
                        y + 7,
                        width,
                        18),
                    2,
                    2);
            }

            if (rowIndex < rows.Length - 1)
            {
                drawingContext.DrawLine(
                    FrozenPen(Color.FromArgb(24, 255, 255, 255), 1),
                    new Point(timelineX, y + 32),
                    new Point(ActualWidth, y + 32));
            }
        }

        if (rows[0].Buckets is { Count: > 0 } axisBuckets)
        {
            var y = rows.Length * 33d + 2;
            DrawAxisText(drawingContext, AxisLabel(axisBuckets[0].Start), new Point(timelineX, y), dpi, TextAlignment.Left);
            DrawAxisText(
                drawingContext,
                AxisLabel(axisBuckets[axisBuckets.Count / 2].Start),
                new Point(timelineX + timelineWidth / 2, y),
                dpi,
                TextAlignment.Center);
            DrawAxisText(
                drawingContext,
                AxisLabel(axisBuckets[^1].Start.AddSeconds(Range.GetDefinition().BucketSeconds)),
                new Point(timelineX + timelineWidth, y),
                dpi,
                TextAlignment.Right);
        }
    }

    private string AxisLabel(DateTimeOffset value) =>
        Range is TypingTimelineRange.SevenDays or TypingTimelineRange.TwentyFourHours
            ? value.ToLocalTime().ToString("MM-dd HH:mm", CultureInfo.CurrentCulture)
            : value.ToLocalTime().ToString("HH:mm", CultureInfo.CurrentCulture);

    private static void DrawAxisText(
        DrawingContext drawingContext,
        string value,
        Point point,
        double dpi,
        TextAlignment alignment)
    {
        var text = new FormattedText(
            value,
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            new Typeface("Cascadia Mono"),
            8,
            FrozenBrush(Color.FromArgb(130, 255, 255, 255)),
            dpi)
        {
            TextAlignment = alignment,
        };
        drawingContext.DrawText(text, point);
    }

    private static void DrawText(
        DrawingContext drawingContext,
        string value,
        Point point,
        double size,
        double dpi,
        bool monospace)
    {
        var text = new FormattedText(
            value,
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            new Typeface(monospace ? "Cascadia Mono" : "Segoe UI Variable"),
            size,
            FrozenBrush(Color.FromArgb(225, 255, 255, 255)),
            dpi)
        {
            MaxTextWidth = monospace ? 74 : 146,
            MaxLineCount = 1,
            Trimming = TextTrimming.CharacterEllipsis,
        };
        drawingContext.DrawText(text, point);
    }

    private static SolidColorBrush FrozenBrush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private static Pen FrozenPen(Color color, double width) => new(FrozenBrush(color), width);
}

public sealed class StatsRhythmHeatmap : FrameworkElement
{
    private const double AxisWidth = 34;
    private const double CellGap = 3;
    private const int HourColumnCount = 24;
    private const double GridTop = 17;

    private readonly List<(Rect Bounds, string Help)> _hitCells = [];
    private readonly ImmediateHeatmapCellDetails _cellDetails;

    public static readonly DependencyProperty ValuesProperty = DependencyProperty.Register(
        nameof(Values),
        typeof(IReadOnlyList<TypingWeekdayHourAggregate>),
        typeof(StatsRhythmHeatmap),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty ModeProperty = DependencyProperty.Register(
        nameof(Mode),
        typeof(StatsRhythmMode),
        typeof(StatsRhythmHeatmap),
        new FrameworkPropertyMetadata(StatsRhythmMode.Difference, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty CurrentRangeProperty = DependencyProperty.Register(
        nameof(CurrentRange),
        typeof(TypingDateRange?),
        typeof(StatsRhythmHeatmap),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty ComparisonRangeProperty = DependencyProperty.Register(
        nameof(ComparisonRange),
        typeof(TypingDateRange?),
        typeof(StatsRhythmHeatmap),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public StatsRhythmHeatmap()
    {
        AutomationProperties.SetName(this, "星期与小时输入节律热力图");
        Focusable = true;
        _cellDetails = new ImmediateHeatmapCellDetails(this, "星期与小时输入节律热力图");
    }

    public IReadOnlyList<TypingWeekdayHourAggregate>? Values
    {
        get => (IReadOnlyList<TypingWeekdayHourAggregate>?)GetValue(ValuesProperty);
        set => SetValue(ValuesProperty, value);
    }

    public StatsRhythmMode Mode
    {
        get => (StatsRhythmMode)GetValue(ModeProperty);
        set => SetValue(ModeProperty, value);
    }

    public TypingDateRange? CurrentRange
    {
        get => (TypingDateRange?)GetValue(CurrentRangeProperty);
        set => SetValue(CurrentRangeProperty, value);
    }

    public TypingDateRange? ComparisonRange
    {
        get => (TypingDateRange?)GetValue(ComparisonRangeProperty);
        set => SetValue(ComparisonRangeProperty, value);
    }

    public static StatsHeatmapGeometry CalculateGeometry(double availableWidth)
    {
        var width = double.IsFinite(availableWidth) ? Math.Max(0, availableWidth) : 442;
        var fittedCell = (width - AxisWidth - (HourColumnCount - 1) * CellGap)
            / HourColumnCount;
        var cell = Math.Clamp(fittedCell, 10, 18);
        var gridWidth = AxisWidth
            + HourColumnCount * cell
            + (HourColumnCount - 1) * CellGap;
        var requiredHeight = GridTop + 7 * cell + 6 * CellGap;
        return new StatsHeatmapGeometry(
            AxisWidth,
            CellGap,
            cell,
            HourColumnCount,
            gridWidth,
            requiredHeight,
            Rect.Empty);
    }

    protected override Size MeasureOverride(Size availableSize)
    {
        var width = double.IsInfinity(availableSize.Width) ? 442 : availableSize.Width;
        var geometry = CalculateGeometry(width);
        return new Size(width, geometry.RequiredHeight);
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        _hitCells.Clear();
        var geometry = CalculateGeometry(ActualWidth);
        var gap = geometry.Gap;
        var axis = geometry.AxisWidth;
        var cell = geometry.CellSize;
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        for (var hour = 0; hour < 24; hour += 3)
        {
            DrawText(
                drawingContext,
                hour.ToString(CultureInfo.InvariantCulture),
                new Point(axis + hour * (cell + gap), 0),
                8,
                dpi);
        }

        var values = Values?.ToDictionary(value => value.Id) ?? [];
        var currentOccurrences = CurrentRange is { } currentRange
            ? StatsVisualizationMath.WeekdayOccurrences(currentRange)
            : Enumerable.Range(1, 7).ToDictionary(value => value, _ => 1);
        var comparisonOccurrences = ComparisonRange is { } comparisonRange
            ? StatsVisualizationMath.WeekdayOccurrences(comparisonRange)
            : Enumerable.Range(1, 7).ToDictionary(value => value, _ => 1);
        var evaluated = values.Values.Select(value => Evaluate(
            value,
            currentOccurrences,
            comparisonOccurrences)).ToArray();
        var heatScale = AdaptiveHeatScale.FromNonZero(
            evaluated.Select(value => Math.Abs(value.DisplayValue)));
        var weekdays = new[] { 2, 3, 4, 5, 6, 7, 1 };
        var titles = new[] { "周一", "周二", "周三", "周四", "周五", "周六", "周日" };
        for (var dayIndex = 0; dayIndex < weekdays.Length; dayIndex++)
        {
            var weekday = weekdays[dayIndex];
            var y = GridTop + dayIndex * (cell + gap);
            DrawText(drawingContext, titles[dayIndex], new Point(0, y + 1), 9, dpi);
            for (var hour = 0; hour < 24; hour++)
            {
                var id = (weekday - 1) * 24 + hour;
                var value = values.GetValueOrDefault(id)
                    ?? new TypingWeekdayHourAggregate(weekday, hour, 0, 0);
                var presentation = Evaluate(value, currentOccurrences, comparisonOccurrences);
                var intensity = Mode == StatsRhythmMode.Current
                    ? heatScale.Normalize(presentation.DisplayValue)
                    : heatScale.NormalizeMagnitude(presentation.DisplayValue);
                Color color;
                string symbol;
                if (Mode == StatsRhythmMode.Current)
                {
                    color = value.CharacterCount > 0
                        ? BattutaHeatmapPalette.RhythmCurrentColor(intensity)
                        : Color.FromArgb(20, 255, 255, 255);
                    symbol = "";
                }
                else if (presentation.DisplayValue > 0)
                {
                    color = BattutaHeatmapPalette.RhythmDifferenceColor(intensity);
                    symbol = intensity >= .34 ? "↑" : "";
                }
                else if (presentation.DisplayValue < 0)
                {
                    color = BattutaHeatmapPalette.RhythmDifferenceColor(-intensity);
                    symbol = intensity >= .34 ? "↓" : "";
                }
                else
                {
                    var hasComparisonData = value.CharacterCount > 0
                        || value.ComparisonCharacterCount > 0;
                    color = hasComparisonData
                        ? BattutaHeatmapPalette.RhythmDifferenceColor(0)
                        : Color.FromArgb(20, 255, 255, 255);
                    symbol = hasComparisonData ? "•" : "";
                }

                var bounds = new Rect(axis + hour * (cell + gap), y, cell, cell);
                drawingContext.DrawRoundedRectangle(
                    FrozenBrush(color),
                    FrozenPen(Color.FromArgb(9, 255, 255, 255), 1),
                    bounds,
                    2,
                    2);
                if (symbol.Length > 0)
                {
                    DrawCentered(drawingContext, symbol, bounds, Math.Max(6, cell * .62), dpi);
                }

                var hourText = $"{hour:00}:00–{(hour + 1) % 24:00}:00";
                var help = Mode == StatsRhythmMode.Current
                    ? $"{titles[dayIndex]} {hourText}：合计 {value.CharacterCount:N0}，平均 {presentation.CurrentAverage:N1}"
                    : $"{titles[dayIndex]} {hourText}：当前 {presentation.CurrentAverage:N1}，上期 {presentation.ComparisonAverage:N1}";
                _hitCells.Add((bounds, help));
            }
        }

        _cellDetails.Synchronize(_hitCells);
        if (_cellDetails.PinnedBounds is { } pinnedBounds)
        {
            drawingContext.DrawRoundedRectangle(
                null,
                FrozenPen(Color.FromArgb(235, 255, 255, 255), 1.5),
                pinnedBounds,
                2,
                2);
        }
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        _cellDetails.Hover(e.GetPosition(this), _hitCells);
    }

    protected override void OnMouseLeave(MouseEventArgs e)
    {
        base.OnMouseLeave(e);
        _cellDetails.HideWhenUnpinned();
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        Focus();
        _cellDetails.Pin(e.GetPosition(this), _hitCells);
        InvalidateVisual();
        e.Handled = true;
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (e.Key == Key.Escape && _cellDetails.ClearPin())
        {
            InvalidateVisual();
            e.Handled = true;
        }
    }

    private RhythmValue Evaluate(
        TypingWeekdayHourAggregate value,
        IReadOnlyDictionary<int, int> currentOccurrences,
        IReadOnlyDictionary<int, int> comparisonOccurrences)
    {
        var current = (double)value.CharacterCount / Math.Max(1, currentOccurrences.GetValueOrDefault(value.Weekday, 1));
        var comparison = (double)value.ComparisonCharacterCount / Math.Max(1, comparisonOccurrences.GetValueOrDefault(value.Weekday, 1));
        var display = Mode == StatsRhythmMode.Current
            ? current
            : StatsVisualizationMath.SignificantDifference(current, comparison);
        return new RhythmValue(current, comparison, display);
    }

    private static void DrawText(
        DrawingContext drawingContext,
        string text,
        Point point,
        double size,
        double dpi) =>
        drawingContext.DrawText(
            new FormattedText(
                text,
                CultureInfo.CurrentUICulture,
                FlowDirection.LeftToRight,
                new Typeface("Segoe UI Variable"),
                size,
                FrozenBrush(Color.FromArgb(148, 255, 255, 255)),
                dpi),
            point);

    private static void DrawCentered(
        DrawingContext drawingContext,
        string text,
        Rect bounds,
        double size,
        double dpi)
    {
        var formatted = new FormattedText(
            text,
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            new Typeface("Segoe UI Variable"),
            size,
            FrozenBrush(Color.FromArgb(220, 255, 255, 255)),
            dpi);
        drawingContext.DrawText(
            formatted,
            new Point(
                bounds.X + (bounds.Width - formatted.Width) / 2,
                bounds.Y + (bounds.Height - formatted.Height) / 2));
    }

    private static SolidColorBrush FrozenBrush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private static Pen FrozenPen(Color color, double width) => new(FrozenBrush(color), width);

    private sealed record RhythmValue(
        double CurrentAverage,
        double ComparisonAverage,
        double DisplayValue);
}

public sealed class StatsYearHeatmap : FrameworkElement
{
    private const double AxisWidth = 34;
    private const double CellGap = 3;
    private const int AnnualWeekCount = 53;
    private const double GridTop = 16;
    private const double LegendTopGap = 8;
    private const double LegendRightInset = 4;
    private const double LegendLabelSlot = 18;
    private const double LegendItemGap = 4;
    private const double BottomPadding = 6;

    private readonly List<(Rect Bounds, string Help)> _hitCells = [];
    private readonly ImmediateHeatmapCellDetails _cellDetails;

    public static readonly DependencyProperty DaysProperty = DependencyProperty.Register(
        nameof(Days),
        typeof(IReadOnlyList<TypingDaySummary>),
        typeof(StatsYearHeatmap),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty RangeProperty = DependencyProperty.Register(
        nameof(Range),
        typeof(TypingDateRange?),
        typeof(StatsYearHeatmap),
        new FrameworkPropertyMetadata(
            null,
            FrameworkPropertyMetadataOptions.AffectsRender | FrameworkPropertyMetadataOptions.AffectsMeasure));

    public StatsYearHeatmap()
    {
        AutomationProperties.SetName(this, "全年输入热力图");
        Focusable = true;
        _cellDetails = new ImmediateHeatmapCellDetails(this, "全年输入热力图");
    }

    public IReadOnlyList<TypingDaySummary>? Days
    {
        get => (IReadOnlyList<TypingDaySummary>?)GetValue(DaysProperty);
        set => SetValue(DaysProperty, value);
    }

    public TypingDateRange? Range
    {
        get => (TypingDateRange?)GetValue(RangeProperty);
        set => SetValue(RangeProperty, value);
    }

    public static StatsHeatmapGeometry CalculateGeometry(
        double availableWidth,
        int weekCount = AnnualWeekCount)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(weekCount, 1);
        var width = double.IsFinite(availableWidth) ? Math.Max(0, availableWidth) : 935;
        var fittedCell = (width - AxisWidth - (weekCount - 1) * CellGap) / weekCount;
        var cell = Math.Clamp(fittedCell, 10, 18);
        var gridWidth = AxisWidth + weekCount * cell + (weekCount - 1) * CellGap;
        var gridBottom = GridTop + 7 * cell + 6 * CellGap;
        var legendTop = gridBottom + LegendTopGap;
        var swatchesWidth = 5 * cell + 4 * CellGap;
        var legendWidth = LegendLabelSlot
            + LegendItemGap
            + swatchesWidth
            + LegendItemGap
            + LegendLabelSlot;
        var legendRight = Math.Max(
            AxisWidth + legendWidth,
            Math.Min(width, gridWidth) - LegendRightInset);
        var legendBounds = new Rect(
            legendRight - legendWidth,
            legendTop,
            legendWidth,
            Math.Max(cell, 12));
        var requiredHeight = legendBounds.Bottom + BottomPadding;
        return new StatsHeatmapGeometry(
            AxisWidth,
            CellGap,
            cell,
            weekCount,
            gridWidth,
            requiredHeight,
            legendBounds);
    }

    protected override Size MeasureOverride(Size availableSize)
    {
        var width = double.IsInfinity(availableSize.Width) ? 935 : availableSize.Width;
        var weekCount = Range is { } range ? WeekCount(range) : AnnualWeekCount;
        var geometry = CalculateGeometry(width, weekCount);
        return new Size(width, geometry.RequiredHeight);
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        _hitCells.Clear();
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var range = Range;
        if (range is null)
        {
            return;
        }

        var start = range.Value.StartDate;
        var end = range.Value.EndDate;
        var mondayOffset = ((int)start.DayOfWeek + 6) % 7;
        var gridStart = start.AddDays(-mondayOffset);
        var endOffset = 6 - (((int)end.DayOfWeek + 6) % 7);
        var gridEnd = end.AddDays(endOffset);
        var weekCount = Math.Max(1, (gridEnd.DayNumber - gridStart.DayNumber) / 7 + 1);
        var geometry = CalculateGeometry(ActualWidth, weekCount);
        var axis = geometry.AxisWidth;
        var gap = geometry.Gap;
        var cell = geometry.CellSize;
        var counts = Days?.ToDictionary(day => day.Date, day => day.CharacterCount) ?? [];
        var visibleCounts = counts
            .Where(pair => pair.Key >= start && pair.Key <= end)
            .Select(pair => pair.Value)
            .ToArray();
        var heatScale = AdaptiveHeatScale.FromNonZero(visibleCounts);
        var monthCursor = start;
        var seenMonth = -1;
        while (monthCursor <= end)
        {
            if (monthCursor.Month != seenMonth)
            {
                var week = Math.Max(0, (monthCursor.DayNumber - gridStart.DayNumber) / 7);
                DrawText(
                    drawingContext,
                    monthCursor.ToString("MMM", CultureInfo.CurrentCulture),
                    new Point(axis + week * (cell + gap), 0),
                    8.5,
                    dpi);
                seenMonth = monthCursor.Month;
            }

            monthCursor = monthCursor.AddDays(1);
        }

        var labels = new[] { "一", "", "三", "", "五", "", "" };
        for (var dayIndex = 0; dayIndex < 7; dayIndex++)
        {
            var y = GridTop + dayIndex * (cell + gap);
            if (labels[dayIndex].Length > 0)
            {
                DrawText(drawingContext, labels[dayIndex], new Point(axis - 15, y + 1), 8, dpi);
            }

            for (var week = 0; week < weekCount; week++)
            {
                var date = gridStart.AddDays(week * 7 + dayIndex);
                if (date < start || date > end)
                {
                    continue;
                }

                var count = counts.GetValueOrDefault(date);
                var intensity = heatScale.Normalize(count);
                var bounds = new Rect(axis + week * (cell + gap), y, cell, cell);
                drawingContext.DrawRoundedRectangle(
                    HeatBrush(count, intensity),
                    FrozenPen(Color.FromArgb(15, 255, 255, 255), .5),
                    bounds,
                    2,
                    2);
                _hitCells.Add((bounds, $"{date:yyyy年M月d日}：{count:N0} 个字符"));
            }
        }

        var legend = geometry.LegendBounds;
        DrawText(drawingContext, "少", new Point(legend.Left, legend.Top), 8.5, dpi);
        var gradientX = legend.Left + LegendLabelSlot + LegendItemGap;
        var gradientWidth = 5 * cell + 4 * gap;
        var gradientBrush = BattutaHeatmapPalette.CreateYearGradientBrush();
        drawingContext.DrawRoundedRectangle(
            gradientBrush,
            FrozenPen(Color.FromArgb(15, 255, 255, 255), .5),
            new Rect(gradientX, legend.Top, gradientWidth, cell),
            2,
            2);

        var highLabelX = gradientX + gradientWidth + LegendItemGap;
        DrawText(
            drawingContext,
            "多",
            new Point(highLabelX, legend.Top),
            8.5,
            dpi);

        _cellDetails.Synchronize(_hitCells);
        if (_cellDetails.PinnedBounds is { } pinnedBounds)
        {
            drawingContext.DrawRoundedRectangle(
                null,
                FrozenPen(Color.FromArgb(235, 255, 255, 255), 1.5),
                pinnedBounds,
                2,
                2);
        }
    }

    private static int WeekCount(TypingDateRange range)
    {
        var mondayOffset = ((int)range.StartDate.DayOfWeek + 6) % 7;
        var gridStart = range.StartDate.AddDays(-mondayOffset);
        var endOffset = 6 - (((int)range.EndDate.DayOfWeek + 6) % 7);
        var gridEnd = range.EndDate.AddDays(endOffset);
        return Math.Max(1, (gridEnd.DayNumber - gridStart.DayNumber) / 7 + 1);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        _cellDetails.Hover(e.GetPosition(this), _hitCells);
    }

    protected override void OnMouseLeave(MouseEventArgs e)
    {
        base.OnMouseLeave(e);
        _cellDetails.HideWhenUnpinned();
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        Focus();
        _cellDetails.Pin(e.GetPosition(this), _hitCells);
        InvalidateVisual();
        e.Handled = true;
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (e.Key == Key.Escape && _cellDetails.ClearPin())
        {
            InvalidateVisual();
            e.Handled = true;
        }
    }

    private static SolidColorBrush HeatBrush(long count, double intensity) =>
        FrozenBrush(
            count > 0
                ? BattutaHeatmapPalette.YearColor(intensity)
                : Color.FromArgb(20, 255, 255, 255));

    private static void DrawText(
        DrawingContext drawingContext,
        string text,
        Point point,
        double size,
        double dpi) =>
        drawingContext.DrawText(
            new FormattedText(
                text,
                CultureInfo.CurrentUICulture,
                FlowDirection.LeftToRight,
                new Typeface("Segoe UI Variable"),
                size,
                FrozenBrush(Color.FromArgb(148, 255, 255, 255)),
                dpi),
            point);

    private static SolidColorBrush FrozenBrush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private static Pen FrozenPen(Color color, double width) => new(FrozenBrush(color), width);
}
