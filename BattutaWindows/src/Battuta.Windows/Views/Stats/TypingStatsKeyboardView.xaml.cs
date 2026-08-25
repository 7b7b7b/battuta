using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using Battuta.Core.Input;
using Battuta.Windows.Stats.Models;

namespace Battuta.Windows.Views.Stats;

public partial class TypingStatsKeyboardView : UserControl
{
    private TypingStatsSnapshot? _snapshot;

    public TypingStatsKeyboardView() => InitializeComponent();

    public void ApplySnapshot(TypingStatsSnapshot? snapshot)
    {
        _snapshot = snapshot;
        ApplyScope();
    }

    private void ScopeChanged(object sender, RoutedEventArgs e)
    {
        if (IsInitialized)
        {
            ApplyScope();
        }
    }

    private void ApplyScope()
    {
        IReadOnlyDictionary<PhysicalKeyId, long> counts = AllTimeScope.IsChecked == true
            ? _snapshot?.AllTimeKeyCounts ?? new Dictionary<PhysicalKeyId, long>()
            : _snapshot?.TodayKeyCounts ?? new Dictionary<PhysicalKeyId, long>();
        KeyboardHeatmap.KeyCounts = counts;
        var total = counts.Values.Sum();
        EmptyKeyText.Text = AllTimeScope.IsChecked == true
            ? "还没有累计按键记录；开始输入后键盘会逐键点亮。"
            : "今天还没有按键记录；开始输入后键盘会逐键点亮。";
        EmptyKeyText.Visibility = total == 0 ? Visibility.Visible : Visibility.Collapsed;

        ExtendedKeyItems.ItemsSource = WindowsAnsiVisualLayoutCatalog.ExtendedKeys
            .Select(definition => new KeyCountItem(
                $"{definition.Label}  ·  {counts.GetValueOrDefault(definition.Id).ToString("N0", CultureInfo.CurrentCulture)}"))
            .ToArray();

        var other = counts
            .Where(pair => !PhysicalKeyCatalog.TryGet(pair.Key, out _))
            .OrderBy(pair => pair.Key.Value, StringComparer.Ordinal)
            .Select(pair => new KeyCountItem(
                $"{pair.Key.Value}  ·  {pair.Value.ToString("N0", CultureInfo.CurrentCulture)}"))
            .ToArray();
        OtherKeyItems.ItemsSource = other;
        OtherKeysHeading.Visibility = other.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        OtherKeyItems.Visibility = other.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    private sealed record KeyCountItem(string Text);
}
