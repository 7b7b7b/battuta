using System.Windows;
using System.Windows.Controls;
using Battuta.TestSupport;
using Battuta.TestSupport.Threading;
using Battuta.Windows.Stats.Models;
using Battuta.Windows.Views.Stats;

namespace Battuta.Windows.Tests.Stats;

public sealed class TypingStatsHistoryResponsiveLayoutTests
{
    private const double MinimumYearGridWidth = 720;
    private static readonly double[] LayoutHeights = [360, 1_600, 500, 1_400, 360, 1_600];

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void StatisticsWindowMinimumWidthBudgetsBothCardsScrollbarAndNonClientFrame()
    {
        StaTestHost.Run(() =>
        {
            using var window = new TypingStatsWindow();
            var requiredWidth = TypingStatsHistoryView.RhythmCardWidth
                + TypingStatsHistoryView.TopPanelGap
                + TypingStatsHistoryView.ApplicationCardMinimumWidth
                + 40 // History page has 20 DIP horizontal margin on each side.
                + SystemParameters.VerticalScrollBarWidth
                + 2 * SystemParameters.ResizeFrameVerticalBorderWidth;

            Assert.Equal(TypingStatsWindow.SafeMinimumWidth, window.MinWidth);
            Assert.Equal(TypingStatsWindow.SafeMinimumWidth, window.Width);
            Assert.True(
                window.MinWidth >= requiredWidth,
                $"MinWidth {window.MinWidth:N1} does not cover the {requiredWidth:N1} DIP safe layout budget.");
        });
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void TopCardsNeverReflowOrOscillateWhenVerticalScrollbarAppearsAndDisappears()
    {
        StaTestHost.Run(() =>
        {
            const double viewWidth = TypingStatsWindow.SafeMinimumWidth;
            var view = new TypingStatsHistoryView
            {
                Width = viewWidth,
            };
            view.ApplyReport(CreateAnnualReport(), isLoading: false, errorMessage: null);

            var scroller = Assert.IsType<ScrollViewer>(view.FindName("HistoryScrollViewer"));
            var topPanels = Assert.IsType<Grid>(view.FindName("TopPanels"));
            var rhythmCard = Assert.IsType<Border>(view.FindName("RhythmCard"));
            var applicationCard = Assert.IsType<Border>(view.FindName("ApplicationCard"));
            var yearHeatmap = Assert.IsType<StatsYearHeatmap>(view.FindName("YearHeatmap"));
            var stableByScrollbarState = new Dictionary<Visibility, LayoutWidths>();
            var observedScrollbarStates = new HashSet<Visibility>();

            double? narrowViewportApplicationWidth = null;
            double? wideViewportApplicationWidth = null;
            foreach (var height in LayoutHeights)
            {
                view.Height = height;
                Arrange(view, viewWidth, height);
                scroller.ScrollToVerticalOffset(height <= 500 ? 120 : 0);
                view.UpdateLayout();
                Arrange(view, viewWidth, height);

                var scrollbarState = scroller.ComputedVerticalScrollBarVisibility;
                observedScrollbarStates.Add(scrollbarState);
                Assert.Contains(scrollbarState, new[] { Visibility.Visible, Visibility.Collapsed });
                Assert.Equal(0, Grid.GetRow(rhythmCard));
                Assert.Equal(0, Grid.GetColumn(rhythmCard));
                Assert.Equal(0, Grid.GetRow(applicationCard));
                Assert.Equal(2, Grid.GetColumn(applicationCard));

                var rhythmOrigin = rhythmCard.TranslatePoint(new Point(), topPanels);
                var applicationOrigin = applicationCard.TranslatePoint(new Point(), topPanels);
                Assert.InRange(Math.Abs(applicationOrigin.Y - rhythmOrigin.Y), 0, 0.5);
                Assert.InRange(
                    rhythmCard.ActualWidth,
                    TypingStatsHistoryView.RhythmCardWidth - 0.5,
                    TypingStatsHistoryView.RhythmCardWidth + 0.5);
                Assert.True(applicationCard.ActualWidth >= 400);
                Assert.InRange(
                    applicationOrigin.X - (rhythmOrigin.X + rhythmCard.ActualWidth),
                    TypingStatsHistoryView.TopPanelGap - 0.5,
                    TypingStatsHistoryView.TopPanelGap + 0.5);
                Assert.True(
                    applicationOrigin.X + applicationCard.ActualWidth <= topPanels.ActualWidth + 0.5);
                Assert.InRange(scroller.ScrollableWidth, 0, 0.5);

                Assert.True(
                    yearHeatmap.ActualWidth >= MinimumYearGridWidth,
                    $"The {height} DIP-high view left only {yearHeatmap.ActualWidth:N1} DIP for the heatmap.");
                var heatmapRight = yearHeatmap.TranslatePoint(
                    new Point(yearHeatmap.ActualWidth, 0),
                    view).X;
                Assert.True(
                    heatmapRight <= scroller.ViewportWidth - 19,
                    $"The year heatmap right edge {heatmapRight:N1} exceeded viewport {scroller.ViewportWidth:N1}.");

                var widths = new LayoutWidths(
                    topPanels.ActualWidth,
                    rhythmCard.ActualWidth,
                    applicationCard.ActualWidth);
                if (stableByScrollbarState.TryGetValue(scrollbarState, out var prior))
                {
                    AssertWidthsEqual(prior, widths);
                }
                else
                {
                    stableByScrollbarState.Add(scrollbarState, widths);
                }

                if (scrollbarState == Visibility.Visible)
                {
                    narrowViewportApplicationWidth = applicationCard.ActualWidth;
                }
                else
                {
                    wideViewportApplicationWidth = applicationCard.ActualWidth;
                }
            }

            Assert.Contains(Visibility.Visible, observedScrollbarStates);
            Assert.Contains(Visibility.Collapsed, observedScrollbarStates);
            Assert.NotNull(narrowViewportApplicationWidth);
            Assert.NotNull(wideViewportApplicationWidth);
            Assert.InRange(
                Math.Abs(wideViewportApplicationWidth.Value - narrowViewportApplicationWidth.Value),
                0,
                SystemParameters.VerticalScrollBarWidth + 0.5);
        });
    }

    private static void Arrange(FrameworkElement element, double width, double height)
    {
        var size = new Size(width, height);
        element.Measure(size);
        element.Arrange(new Rect(size));
        element.UpdateLayout();

        // A second pass verifies that repeated WPF layout does not change the grid.
        element.InvalidateMeasure();
        element.Measure(size);
        element.Arrange(new Rect(size));
        element.UpdateLayout();
    }

    private static void AssertWidthsEqual(LayoutWidths expected, LayoutWidths actual)
    {
        Assert.InRange(Math.Abs(actual.TopPanels - expected.TopPanels), 0, 0.5);
        Assert.InRange(Math.Abs(actual.RhythmCard - expected.RhythmCard), 0, 0.5);
        Assert.InRange(Math.Abs(actual.ApplicationCard - expected.ApplicationCard), 0, 0.5);
    }

    private readonly record struct LayoutWidths(
        double TopPanels,
        double RhythmCard,
        double ApplicationCard);

    private static TypingRangeReportSnapshot CreateAnnualReport()
    {
        var generatedAt = new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero);
        var endDate = new DateOnly(2026, 8, 24);
        var range = new TypingDateRange(endDate.AddDays(-364), endDate);
        var comparisonRange = new TypingDateRange(endDate.AddDays(-729), endDate.AddDays(-365));
        var applications = Enumerable.Range(1, 8)
            .Select(index => new TypingApplicationIdentity(
                $"win32:fixture:{index}",
                $"示例应用 {index}",
                $"fixture-{index}.exe"))
            .ToArray();
        var days = Enumerable.Range(0, 365)
            .Select(index => new TypingDaySummary(
                range.StartDate.AddDays(index),
                100 + index,
                4 + index % 8,
                2,
                90,
                applications[index % applications.Length].DisplayName,
                generatedAt))
            .ToArray();
        var weekdays = Enumerable.Range(1, 7)
            .Select(weekday => new TypingWeekdayAggregate(weekday, weekday * 1_000, 52))
            .ToArray();
        var hours = Enumerable.Range(0, 24)
            .Select(hour => new TypingHourAggregate(hour, (hour + 1) * 500, 100, 12))
            .ToArray();
        var metrics = new TypingRangeMetrics(
            days.Sum(day => day.CharacterCount),
            365,
            365,
            days.Average(day => day.CharacterCount),
            days.Average(day => day.CharacterCount),
            11,
            days[^1],
            365,
            weekdays[^1],
            hours[^1]);
        var applicationRows = applications
            .Select((application, index) => new TypingRangeApplicationSummary(
                application,
                20_000 - index * 1_000,
                18_000 - index * 900,
                300,
                290,
                0.2 - index * 0.01,
                0.18 - index * 0.01,
                2_000 - index * 100,
                0.1))
            .ToArray();
        var rhythm = Enumerable.Range(1, 7)
            .SelectMany(weekday => Enumerable.Range(0, 24).Select(hour =>
                new TypingWeekdayHourAggregate(
                    weekday,
                    hour,
                    weekday * 1_000 + hour * 10,
                    weekday * 900 + hour * 8)))
            .ToArray();

        return new TypingRangeReportSnapshot(
            generatedAt,
            range,
            comparisonRange,
            metrics,
            metrics,
            days,
            weekdays,
            hours,
            rhythm,
            applicationRows,
            new TypingReportDataCoverage(range.StartDate, range.EndDate, 365, 365, true));
    }
}
