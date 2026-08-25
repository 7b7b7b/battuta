using Battuta.Core.Input;
using Battuta.TestSupport;
using Battuta.TestSupport.Threading;
using Battuta.Windows.Stats.Models;
using Battuta.Windows.Controls.Keyboard;
using Battuta.Windows.Views.Stats;
using System.Windows.Automation.Peers;

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
    public void YearHeatLevelIsLogarithmicAndZeroSafe()
    {
        Assert.Equal(0, StatsVisualizationMath.YearHeatLevel(0, 10_000));
        Assert.InRange(StatsVisualizationMath.YearHeatLevel(1, 10_000), 1, 4);
        Assert.Equal(4, StatsVisualizationMath.YearHeatLevel(10_000, 10_000));
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
