using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Battuta.Windows.Stats.Models;

namespace Battuta.Windows.Views.Stats;

public partial class TypingStatsHistoryView : UserControl
{
    public const double RhythmCardWidth = 530;
    public const double TopPanelGap = 16;
    public const double ApplicationCardMinimumWidth = 400;

    private static readonly Brush IncreaseBrush = FrozenBrush(Color.FromRgb(184, 232, 77));
    private static readonly Brush DecreaseBrush = FrozenBrush(Color.FromRgb(245, 97, 89));
    private static readonly Brush NeutralBrush = FrozenBrush(Color.FromArgb(150, 255, 255, 255));

    public TypingStatsHistoryView()
    {
        InitializeComponent();
    }

    public void ApplyReport(
        TypingRangeReportSnapshot? report,
        bool isLoading,
        string? errorMessage)
    {
        ErrorBanner.Visibility = string.IsNullOrWhiteSpace(errorMessage)
            ? Visibility.Collapsed
            : Visibility.Visible;
        ErrorText.Text = errorMessage ?? string.Empty;

        if (report is null)
        {
            ReportContent.Visibility = Visibility.Collapsed;
            LoadingState.Visibility = isLoading ? Visibility.Visible : Visibility.Collapsed;
            EmptyState.Visibility = isLoading ? Visibility.Collapsed : Visibility.Visible;
            return;
        }

        LoadingState.Visibility = Visibility.Collapsed;
        EmptyState.Visibility = Visibility.Collapsed;
        ReportContent.Visibility = Visibility.Visible;
        ReportContent.Opacity = isLoading ? .62 : 1;

        RhythmHeatmap.Values = report.WeekdayHourDistribution;
        RhythmHeatmap.CurrentRange = report.Range;
        RhythmHeatmap.ComparisonRange = report.ComparisonRange;
        DifferenceRhythm.IsEnabled = report.ComparisonRange is not null;
        if (report.ComparisonRange is null)
        {
            CurrentRhythm.IsChecked = true;
        }

        ApplyRhythmMode();
        ApplicationCountText.Text = $"{report.Applications.Count:N0} 个应用";
        var rows = report.Applications.Select(CreateApplicationRow).ToArray();
        ApplicationRows.ItemsSource = rows;
        ApplicationsEmptyText.Visibility = rows.Length == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        ApplicationsScroll.Visibility = rows.Length == 0
            ? Visibility.Collapsed
            : Visibility.Visible;

        YearRangeText.Text =
            $"{report.Range.StartDate:yyyy年M月d日} – {report.Range.EndDate:yyyy年M月d日} · 每个方格代表一天，颜色越亮表示输入越多";
        YearHeatmap.Range = report.Range;
        YearHeatmap.Days = report.Days;

        var metrics = report.Metrics;
        BestDayValue.Text = metrics.BestDay is { } bestDay
            ? bestDay.CharacterCount.ToString("N0", CultureInfo.CurrentCulture)
            : "—";
        BestDayDetail.Text = metrics.BestDay is { } datedBest
            ? datedBest.Date.ToString("M月d日", CultureInfo.CurrentCulture)
            : "暂无输入";
        LongestStreakValue.Text = $"{metrics.LongestActiveDayStreak:N0} 天";
        BusiestWeekdayValue.Text = WeekdayName(metrics.BusiestWeekday?.Weekday);
        BusiestWeekdayDetail.Text = metrics.BusiestWeekday is { } weekday
            ? $"合计 {weekday.CharacterCount:N0} 个字符"
            : "暂无输入";
        BusiestHourValue.Text = metrics.BusiestHour is { } hour
            ? $"{hour.Hour:00}:00–{(hour.Hour + 1) % 24:00}:00"
            : "—";
        BusiestHourDetail.Text = metrics.BusiestHour is { } busiestHour
            ? $"合计 {busiestHour.CharacterCount:N0} 个字符"
            : "暂无输入";
    }

    private void RhythmModeChanged(object sender, RoutedEventArgs e)
    {
        if (!IsInitialized)
        {
            return;
        }

        ApplyRhythmMode();
    }

    private void ApplyRhythmMode()
    {
        var difference = DifferenceRhythm.IsChecked == true && DifferenceRhythm.IsEnabled;
        RhythmHeatmap.Mode = difference
            ? StatsRhythmMode.Difference
            : StatsRhythmMode.Current;
        DifferenceLegend.Visibility = difference ? Visibility.Visible : Visibility.Collapsed;
        CurrentLegend.Visibility = difference ? Visibility.Collapsed : Visibility.Visible;
    }

    private static ApplicationChangeRow CreateApplicationRow(
        TypingRangeApplicationSummary application)
    {
        string change;
        Brush brush;
        if (application.ComparisonCharacterCount == 0)
        {
            change = application.CharacterCount > 0 ? "新增" : "持平";
            brush = application.CharacterCount > 0 ? IncreaseBrush : NeutralBrush;
        }
        else if (application.CharacterChange > 0)
        {
            var percentage = Math.Abs(application.RelativeCharacterChange ?? 0) * 100;
            change = $"+{application.CharacterChange:N0}  ↑ {percentage:N1}%";
            brush = IncreaseBrush;
        }
        else if (application.CharacterChange < 0)
        {
            var percentage = Math.Abs(application.RelativeCharacterChange ?? 0) * 100;
            change = $"−{Math.Abs(application.CharacterChange):N0}  ↓ {percentage:N1}%";
            brush = DecreaseBrush;
        }
        else
        {
            change = "持平";
            brush = NeutralBrush;
        }

        return new ApplicationChangeRow(
            application.Application.DisplayName,
            application.CharacterCount.ToString("N0", CultureInfo.CurrentCulture),
            application.ComparisonCharacterCount.ToString("N0", CultureInfo.CurrentCulture),
            change,
            brush);
    }

    private static string WeekdayName(int? weekday) => weekday switch
    {
        1 => "周日",
        2 => "周一",
        3 => "周二",
        4 => "周三",
        5 => "周四",
        6 => "周五",
        7 => "周六",
        _ => "—",
    };

    private static SolidColorBrush FrozenBrush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private sealed record ApplicationChangeRow(
        string Name,
        string Current,
        string Previous,
        string Change,
        Brush ChangeBrush);
}
