using System.Windows;
using System.Windows.Controls;
using Battuta.TestSupport;
using Battuta.TestSupport.Threading;
using Battuta.Windows.Stats.Models;
using Battuta.Windows.Views.Stats;

namespace Battuta.Windows.Tests.Stats;

public sealed class StatsHeatmapLayoutTests
{
    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void HistoryHeatmapsFillAllColumnsAndKeepYearLegendInsideTheControl()
    {
        StaTestHost.Run(() =>
        {
            const double viewHeight = 1_600;
            var view = new TypingStatsHistoryView
            {
                Width = TypingStatsWindow.SafeMinimumWidth,
                Height = viewHeight,
            };
            Assert.IsType<StackPanel>(view.FindName("LoadingState")).Visibility = Visibility.Collapsed;
            Assert.IsType<StackPanel>(view.FindName("EmptyState")).Visibility = Visibility.Collapsed;
            Assert.IsType<StackPanel>(view.FindName("ReportContent")).Visibility = Visibility.Visible;

            var endDate = new DateOnly(2026, 8, 24);
            var yearHeatmap = Assert.IsType<StatsYearHeatmap>(view.FindName("YearHeatmap"));
            yearHeatmap.Range = new TypingDateRange(endDate.AddDays(-364), endDate);
            Arrange(view, TypingStatsWindow.SafeMinimumWidth, viewHeight);

            var rhythmHeatmap = Assert.IsType<StatsRhythmHeatmap>(
                view.FindName("RhythmHeatmap"));
            var rhythmGeometry = StatsRhythmHeatmap.CalculateGeometry(
                rhythmHeatmap.ActualWidth);
            Assert.Equal(24, rhythmGeometry.ColumnCount);
            Assert.InRange(
                Math.Abs(rhythmGeometry.GridWidth - rhythmHeatmap.ActualWidth),
                0,
                0.5);
            Assert.InRange(rhythmGeometry.RightRemainder(rhythmHeatmap.ActualWidth), 0, 0.5);

            var yearGeometry = StatsYearHeatmap.CalculateGeometry(
                yearHeatmap.ActualWidth,
                weekCount: 53);
            Assert.Equal(53, yearGeometry.ColumnCount);
            Assert.InRange(
                Math.Abs(yearGeometry.GridWidth - yearHeatmap.ActualWidth),
                0,
                0.5);
            Assert.InRange(yearGeometry.RightRemainder(yearHeatmap.ActualWidth), 0, 0.5);
            Assert.False(yearGeometry.LegendBounds.IsEmpty);
            Assert.True(yearGeometry.LegendBounds.Left >= 0);
            Assert.True(yearGeometry.LegendBounds.Top >= 0);
            Assert.True(yearGeometry.LegendBounds.Right <= yearHeatmap.ActualWidth + 0.5);
            Assert.True(yearGeometry.LegendBounds.Bottom <= yearHeatmap.ActualHeight + 0.5);
            Assert.True(yearHeatmap.ActualHeight >= yearGeometry.RequiredHeight - 0.5);
        });
    }

    private static void Arrange(FrameworkElement element, double width, double height)
    {
        var size = new Size(width, height);
        element.Measure(size);
        element.Arrange(new Rect(size));
        element.UpdateLayout();
    }
}
