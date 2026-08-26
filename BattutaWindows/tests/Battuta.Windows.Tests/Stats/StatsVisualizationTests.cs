using Battuta.Core.Input;
using Battuta.TestSupport;
using Battuta.TestSupport.Threading;
using Battuta.Windows.Stats.Models;
using Battuta.Windows.Stats.Visualization;
using Battuta.Windows.Controls.Keyboard;
using Battuta.Windows.Views.Stats;
using System.Windows;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Media;

namespace Battuta.Windows.Tests.Stats;

public sealed class StatsVisualizationTests
{
    [Fact]
    public void TrendSmoothingUsesSwiftWeighting()
    {
        var smoothed = StatsVisualizationMath.Smooth([0, 0, 9, 0, 0]);

        Assert.Equal([1.5, 2.25, 3, 2.25, 1.5], smoothed);
    }

    [Theory]
    [InlineData(100, 96, 0)]
    [InlineData(110, 100, 10)]
    [InlineData(90, 100, -10)]
    [InlineData(3, 0, 3)]
    public void RhythmDifferenceAppliesFivePercentAndAbsoluteDeadZone(
        double current,
        double comparison,
        double expected)
    {
        Assert.Equal(expected, StatsVisualizationMath.SignificantDifference(current, comparison));
    }

    [Fact]
    public void AdaptiveHeatScaleUsesVisibleNonZeroMinimumAndSmallSampleMaximum()
    {
        var scale = AdaptiveHeatScale.FromNonZero(new long[] { 0, 5, 10, 15 });

        Assert.Equal(5, scale.Low);
        Assert.Equal(15, scale.High);
        Assert.Equal(0, scale.Normalize(0));
        Assert.Equal(0, scale.Normalize(5));
        Assert.Equal(.5, scale.Normalize(10), 10);
        Assert.Equal(1, scale.Normalize(15));
    }

    [Fact]
    public void AdaptiveHeatScaleUsesP95AndClampsOutliersForLargeSamples()
    {
        var values = Enumerable.Range(1, 100)
            .Select(value => (double)value)
            .Append(10_000);

        var scale = AdaptiveHeatScale.FromNonZero(values);

        Assert.Equal(1, scale.Low);
        Assert.Equal(96, scale.High);
        Assert.Equal(.5, scale.Normalize(48.5), 10);
        Assert.Equal(1, scale.Normalize(10_000));
        Assert.Equal(.5, scale.NormalizeMagnitude(-48), 10);
    }

    [Fact]
    public void HeatmapPalettesRestoreViewSpecificGreenAndCyanRamps()
    {
        Assert.Equal(
            Color.FromArgb(0x19, 0xB8, 0xE8, 0x4D),
            BattutaHeatmapPalette.KeyboardFillColor(0));
        Assert.Equal(
            Color.FromArgb(0x8E, 0xB8, 0xE8, 0x4D),
            BattutaHeatmapPalette.KeyboardFillColor(1));
        Assert.Equal(
            Color.FromArgb(0x42, 0xB8, 0xE8, 0x4D),
            BattutaHeatmapPalette.KeyboardBorderColor(0));
        Assert.Equal(
            Color.FromArgb(0x99, 0xB8, 0xE8, 0x4D),
            BattutaHeatmapPalette.KeyboardBorderColor(1));
        Assert.Equal(
            Color.FromArgb(0x48, 0x40, 0xB8, 0xD1),
            BattutaHeatmapPalette.ApplicationTimelineColor(0));
        Assert.Equal(
            Color.FromArgb(0xFF, 0x91, 0xC9, 0x2B),
            BattutaHeatmapPalette.ApplicationTimelineColor(1));
        Assert.Equal(
            Color.FromArgb(0x48, 0x40, 0xB8, 0xD1),
            BattutaHeatmapPalette.ApplicationTimelineColor(.249));
        Assert.Equal(
            Color.FromArgb(0x8C, 0x40, 0xB8, 0xD1),
            BattutaHeatmapPalette.ApplicationTimelineColor(.25));
        Assert.Equal(
            Color.FromArgb(0xB8, 0xB8, 0xE8, 0x4D),
            BattutaHeatmapPalette.ApplicationTimelineColor(.55));
        Assert.Equal(
            Color.FromArgb(0xFF, 0x91, 0xC9, 0x2B),
            BattutaHeatmapPalette.ApplicationTimelineColor(.82));
        Assert.Equal(
            Color.FromArgb(0x28, 0xB8, 0xE8, 0x4D),
            BattutaHeatmapPalette.RhythmCurrentColor(0));
        Assert.Equal(
            Color.FromArgb(0xC1, 0xB8, 0xE8, 0x4D),
            BattutaHeatmapPalette.RhythmCurrentColor(1));
        Assert.Equal(
            Color.FromArgb(0x3D, 0xB8, 0xE8, 0x4D),
            BattutaHeatmapPalette.YearColor(0));
        Assert.Equal(
            Color.FromArgb(0xEB, 0xB8, 0xE8, 0x4D),
            BattutaHeatmapPalette.YearColor(1));
    }

    [Fact]
    public void HeatmapPaletteInterpolatesAlphaAndKeepsRhythmZeroNeutral()
    {
        Assert.Equal(
            Color.FromArgb(0xB7, 0x40, 0xB8, 0xD1),
            BattutaHeatmapPalette.RhythmDifferenceColor(-1));
        Assert.Equal(
            Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF),
            BattutaHeatmapPalette.RhythmDifferenceColor(0));
        Assert.Equal(
            Color.FromArgb(0xC1, 0xB8, 0xE8, 0x4D),
            BattutaHeatmapPalette.RhythmDifferenceColor(1));

        var middle = BattutaHeatmapPalette.RhythmCurrentColor(.5);
        Assert.InRange((int)middle.A, 0x74, 0x75);
        Assert.Equal((byte)0xB8, middle.R);
        Assert.Equal((byte)0xE8, middle.G);
        Assert.Equal((byte)0x4D, middle.B);
    }

    [Fact]
    public void HeatmapColorBarsRemainContinuousAndUseAlphaStops()
    {
        var keyboardGradient = BattutaHeatmapPalette.CreateKeyboardGradientBrush();
        var timelineGradient = BattutaHeatmapPalette.CreateApplicationTimelineGradientBrush();
        var rhythmGradient = BattutaHeatmapPalette.CreateRhythmCurrentGradientBrush();
        var differenceGradient = BattutaHeatmapPalette.CreateRhythmDifferenceGradientBrush();
        var yearGradient = BattutaHeatmapPalette.CreateYearGradientBrush();

        Assert.True(keyboardGradient.IsFrozen);
        Assert.Equal(
            new[] { 0d, .33, .67, 1d },
            keyboardGradient.GradientStops.Select(stop => stop.Offset));
        Assert.Equal(
            new[] { 0x1A, 0x40, 0x66, 0x8F },
            keyboardGradient.GradientStops.Select(stop => (int)stop.Color.A));
        Assert.True(timelineGradient.IsFrozen);
        Assert.Equal(
            new[] { 0d, .33, .67, 1d },
            timelineGradient.GradientStops.Select(stop => stop.Offset));
        Assert.True(rhythmGradient.IsFrozen);
        Assert.Equal(
            new[] { 0x28, 0xC1 },
            rhythmGradient.GradientStops.Select(stop => (int)stop.Color.A));
        Assert.True(differenceGradient.IsFrozen);
        Assert.Equal(
            new[] { 0d, .45, .5, .55, 1d },
            differenceGradient.GradientStops.Select(stop => stop.Offset));
        Assert.Equal(
            Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF),
            differenceGradient.GradientStops[2].Color);
        Assert.True(yearGradient.IsFrozen);
        Assert.Equal(
            new[] { 0x3D, 0x6B, 0xA8, 0xEB },
            yearGradient.GradientStops.Select(stop => (int)stop.Color.A));
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void HeatmapCellDetailsUseZeroDelayTooltips()
    {
        StaTestHost.Run(() =>
        {
            FrameworkElement[] heatmaps =
            [
                new StatsRhythmHeatmap(),
                new StatsYearHeatmap(),
                new KeyboardCanvas(),
            ];

            foreach (var heatmap in heatmaps)
            {
                Assert.Equal(0, ToolTipService.GetInitialShowDelay(heatmap));
                Assert.Equal(0, ToolTipService.GetBetweenShowDelay(heatmap));
                Assert.Equal(int.MaxValue, ToolTipService.GetShowDuration(heatmap));
                Assert.False(ToolTipService.GetIsEnabled(heatmap));
            }
        });
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void ClickingPinnedHeatmapCellAgainClearsThePin()
    {
        StaTestHost.Run(() =>
        {
            var owner = new Border();
            var details = new ImmediateHeatmapCellDetails(owner, "Heatmap");
            IReadOnlyList<(Rect Bounds, string Help)> cells =
            [
                (new Rect(0, 0, 20, 20), "2026-08-26: 42 characters"),
            ];

            details.Pin(new Point(10, 10), cells);
            Assert.True(details.IsPinned);

            details.Pin(new Point(10, 10), cells);
            Assert.False(details.IsPinned);
            Assert.Null(details.PinnedBounds);
        });
    }

    [Fact]
    public void AnnualRangesAreTwoAdjacentInclusive365DayPeriods()
    {
        var today = new DateOnly(2026, 8, 24);
        var ranges = TypingStatsReportRanges.Annual(today);

        Assert.Equal(365, ranges.Current.DayCount);
        Assert.Equal(365, ranges.Comparison.DayCount);
        Assert.Equal(ranges.Comparison.EndDate.AddDays(1), ranges.Current.StartDate);
    }

    [Theory]
    [InlineData(498)]
    [InlineData(530)]
    public void RhythmGeometryFillsTwentyFourColumnsWithoutRightGutter(double width)
    {
        var geometry = StatsRhythmHeatmap.CalculateGeometry(width);

        Assert.Equal(24, geometry.ColumnCount);
        Assert.InRange(geometry.RightRemainder(width), 0, 0.01);
        Assert.True(geometry.CellSize >= 10);
    }

    [Theory]
    [InlineData(995)]
    [InlineData(1048)]
    public void YearGeometryFillsFiftyThreeWeeksAndContainsLegend(double width)
    {
        var geometry = StatsYearHeatmap.CalculateGeometry(width);

        Assert.Equal(53, geometry.ColumnCount);
        Assert.InRange(geometry.RightRemainder(width), 0, 0.01);
        Assert.True(geometry.LegendBounds.Left >= geometry.AxisWidth);
        Assert.True(geometry.LegendBounds.Right <= width);
        Assert.True(geometry.LegendBounds.Bottom < geometry.RequiredHeight);
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void StatsViewsAcceptRealSnapshotAndReportOnSta()
    {
        StaTestHost.Run(() =>
        {
            var today = new DateOnly(2026, 8, 24);
            var app = new TypingApplicationIdentity("win32:test", "Editor", "editor.exe");
            var day = new TypingDaySummary(today, 12, 4, 2, 2, "Editor", DateTimeOffset.Now);
            var buckets = Enumerable.Range(0, 60)
                .Select(index => new TypingBucket(
                    index,
                    DateTimeOffset.Now.AddMinutes(index - 60),
                    index % 5))
                .ToArray();
            var timeline = new TypingAppTimeline(app, buckets);
            var snapshot = new TypingStatsSnapshot(
                DateTimeOffset.Now,
                DateTimeOffset.Now,
                day,
                TypingTimelineRange.OneHour,
                buckets,
                [new TypingAppSummary("win32:test", "Editor", "editor.exe", null, 12, 2, 2, 4)],
                [timeline],
                Enumerable.Repeat(day, 14).ToArray(),
                new Dictionary<PhysicalKeyId, long> { [PhysicalKeys.KeyA] = 5 },
                new Dictionary<PhysicalKeyId, long> { [PhysicalKeys.KeyA] = 9 });

            var range = new TypingDateRange(today.AddDays(-364), today);
            var weekdays = Enumerable.Range(1, 7)
                .Select(value => new TypingWeekdayAggregate(value, value == 2 ? 12 : 0, value == 2 ? 1 : 0))
                .ToArray();
            var hours = Enumerable.Range(0, 24)
                .Select(value => new TypingHourAggregate(value, value == 12 ? 12 : 0, value == 12 ? 1 : 0, value == 12 ? 4 : 0))
                .ToArray();
            var metrics = new TypingRangeMetrics(12, 365, 1, 12d / 365, 12, 4, day, 1, weekdays[1], hours[12]);
            var report = new TypingRangeReportSnapshot(
                DateTimeOffset.Now,
                range,
                new TypingDateRange(today.AddDays(-729), today.AddDays(-365)),
                metrics,
                metrics,
                Enumerable.Range(0, 365).Select(offset => day with { Date = range.StartDate.AddDays(offset) }).ToArray(),
                weekdays,
                hours,
                Enumerable.Range(1, 7).SelectMany(weekday => Enumerable.Range(0, 24).Select(hour =>
                    new TypingWeekdayHourAggregate(weekday, hour, weekday == 2 && hour == 12 ? 12 : 0, 0))).ToArray(),
                [new TypingRangeApplicationSummary(app, 12, 7, 1, 1, 1, 1, 5, 5d / 7)],
                new TypingReportDataCoverage(range.StartDate, range.EndDate, 365, 1, true));

            new TypingStatsOverviewView().ApplySnapshot(snapshot);
            new TypingStatsKeyboardView().ApplySnapshot(snapshot);
            new TypingStatsHistoryView().ApplyReport(report, false, null);
        });
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void StatisticsWindowUsesNativeResizableChrome()
    {
        StaTestHost.Run(() =>
        {
            using var window = new TypingStatsWindow();

            Assert.Equal(System.Windows.WindowStyle.SingleBorderWindow, window.WindowStyle);
            Assert.False(window.AllowsTransparency);
            Assert.Equal(System.Windows.ResizeMode.CanResize, window.ResizeMode);
        });
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void KeyboardCanvasSelectionAndCountsUseStablePhysicalIds()
    {
        StaTestHost.Run(() =>
        {
            var canvas = new KeyboardCanvas
            {
                Mode = KeyboardCanvasMode.Statistics,
                SelectedKey = PhysicalKeys.KeyA,
                KeyCounts = new Dictionary<PhysicalKeyId, long>
                {
                    [PhysicalKeys.KeyA] = 42,
                    [new PhysicalKeyId("win.scan.e0.005E")] = 3,
                },
            };

            Assert.Equal(PhysicalKeys.KeyA, canvas.SelectedKey);
            Assert.Equal(42, canvas.KeyCounts[PhysicalKeys.KeyA]);
            Assert.Equal(
                WindowsAnsiVisualLayoutCatalog.CompactAnsi.KeyIds.Count,
                WindowsAnsiVisualLayoutCatalog.MainKeys.Count);

            canvas.Measure(new System.Windows.Size(691, 282));
            canvas.Arrange(new System.Windows.Rect(0, 0, 691, 282));
            var peer = UIElementAutomationPeer.CreatePeerForElement(canvas);
            var children = peer.GetChildren();
            Assert.Equal(WindowsAnsiVisualLayoutCatalog.MainKeys.Count, children.Count);
            var keyA = Assert.Single(children, child => child.GetAutomationId() == "keyboard.key.KeyA");
            Assert.Equal("A", keyA.GetName());
            Assert.Contains("42", keyA.GetHelpText(), StringComparison.Ordinal);
        });
    }
}
