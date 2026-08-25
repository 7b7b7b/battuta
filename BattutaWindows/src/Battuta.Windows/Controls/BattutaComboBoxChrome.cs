using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Threading;

namespace Battuta.Windows.Controls;

/// <summary>
/// Recolors the visual chrome produced by WPF's native ComboBox themes.
/// No control template or pointer/selection event is replaced; the helper only
/// applies local brush values after the system template has created its visuals.
/// </summary>
public static class BattutaComboBoxChrome
{
    public static readonly DependencyProperty IsEnabledProperty =
        DependencyProperty.RegisterAttached(
            "IsEnabled",
            typeof(bool),
            typeof(BattutaComboBoxChrome),
            new PropertyMetadata(false, IsEnabledChanged));

    private static readonly ConditionalWeakTable<ComboBox, ChromeState> States = new();
    private static readonly Brush FallbackSurface = FrozenBrush(Color.FromRgb(37, 41, 37));
    private static readonly Brush FallbackSeparator = FrozenBrush(Color.FromArgb(92, 255, 255, 255));
    private static readonly Brush FallbackPrimary = FrozenBrush(Color.FromArgb(240, 255, 255, 255));
    private static readonly Brush FallbackHover = FrozenBrush(Color.FromRgb(47, 67, 29));
    private static readonly Brush FallbackSelected = FrozenBrush(Color.FromRgb(74, 122, 10));
    private static readonly Brush FallbackSelectedHover = FrozenBrush(Color.FromRgb(86, 141, 13));
    private static readonly Brush FallbackAccent = FrozenBrush(Color.FromRgb(145, 201, 43));

    public static bool GetIsEnabled(DependencyObject element) =>
        (bool)element.GetValue(IsEnabledProperty);

    public static void SetIsEnabled(DependencyObject element, bool value) =>
        element.SetValue(IsEnabledProperty, value);

    /// <summary>Forces a brush-only refresh and is exposed for STA visual tests.</summary>
    public static void Refresh(ComboBox comboBox)
    {
        ArgumentNullException.ThrowIfNull(comboBox);
        if (States.TryGetValue(comboBox, out var state))
        {
            state.RefreshAll();
        }
    }

    private static void IsEnabledChanged(
        DependencyObject dependencyObject,
        DependencyPropertyChangedEventArgs eventArgs)
    {
        if (dependencyObject is not ComboBox comboBox)
        {
            return;
        }

        if (eventArgs.NewValue is true)
        {
            States.GetValue(comboBox, static combo => new ChromeState(combo)).Attach();
        }
        else if (States.TryGetValue(comboBox, out var state))
        {
            state.Detach();
            _ = States.Remove(comboBox);
        }
    }

    private static Brush ResourceBrush(FrameworkElement owner, string key, Brush fallback) =>
        owner.TryFindResource(key) as Brush ?? fallback;

    private static SolidColorBrush FrozenBrush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private static IEnumerable<T> Descendants<T>(DependencyObject root)
        where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            if (child is T match)
            {
                yield return match;
            }

            foreach (var descendant in Descendants<T>(child))
            {
                yield return descendant;
            }
        }
    }

    private sealed class ChromeState
    {
        private readonly ComboBox comboBox;
        private readonly HashSet<ComboBoxItem> hookedItems = [];
        private readonly DependencyPropertyDescriptor? highlightedDescriptor =
            DependencyPropertyDescriptor.FromProperty(
                ComboBoxItem.IsHighlightedProperty,
                typeof(ComboBoxItem));
        private bool attached;

        public ChromeState(ComboBox comboBox)
        {
            this.comboBox = comboBox;
        }

        public void Attach()
        {
            if (attached)
            {
                return;
            }

            attached = true;
            comboBox.Loaded += ComboBoxLoaded;
            comboBox.Unloaded += ComboBoxUnloaded;
            comboBox.DropDownOpened += DropDownOpened;
            comboBox.SelectionChanged += SelectionChanged;
            comboBox.IsEnabledChanged += ComboBoxIsEnabledChanged;
            comboBox.ItemContainerGenerator.StatusChanged += ContainerStatusChanged;
            if (comboBox.IsLoaded)
            {
                ScheduleRefresh();
            }
        }

        public void Detach()
        {
            if (!attached)
            {
                return;
            }

            attached = false;
            comboBox.Loaded -= ComboBoxLoaded;
            comboBox.Unloaded -= ComboBoxUnloaded;
            comboBox.DropDownOpened -= DropDownOpened;
            comboBox.SelectionChanged -= SelectionChanged;
            comboBox.IsEnabledChanged -= ComboBoxIsEnabledChanged;
            comboBox.ItemContainerGenerator.StatusChanged -= ContainerStatusChanged;
            UnhookItems();
        }

        public void RefreshAll()
        {
            _ = comboBox.ApplyTemplate();
            RefreshClosedChrome();
            HookAndRefreshItems();
        }

        private void ComboBoxLoaded(object sender, RoutedEventArgs eventArgs) => ScheduleRefresh();

        private void ComboBoxUnloaded(object sender, RoutedEventArgs eventArgs) => UnhookItems();

        private void DropDownOpened(object? sender, EventArgs eventArgs) => ScheduleRefresh();

        private void SelectionChanged(object sender, SelectionChangedEventArgs eventArgs) => ScheduleRefresh();

        private void ComboBoxIsEnabledChanged(object sender, DependencyPropertyChangedEventArgs eventArgs) =>
            ScheduleRefresh();

        private void ContainerStatusChanged(object? sender, EventArgs eventArgs)
        {
            if (comboBox.ItemContainerGenerator.Status == GeneratorStatus.ContainersGenerated)
            {
                ScheduleRefresh();
            }
        }

        private void ScheduleRefresh()
        {
            if (!attached || comboBox.Dispatcher.HasShutdownStarted)
            {
                return;
            }

            _ = comboBox.Dispatcher.BeginInvoke(
                DispatcherPriority.Render,
                RefreshAll);
        }

        private void RefreshClosedChrome()
        {
            var surface = ResourceBrush(comboBox, "ComboBox.Static.Background", FallbackSurface);
            var separator = ResourceBrush(comboBox, "ComboBox.Static.Border", FallbackSeparator);
            comboBox.Background = surface;
            comboBox.BorderBrush = separator;

            foreach (var toggle in Descendants<ToggleButton>(comboBox))
            {
                toggle.Background = surface;
                toggle.BorderBrush = separator;
                toggle.Foreground = FallbackPrimary;
            }

            foreach (var border in Descendants<Border>(comboBox))
            {
                if (border.ActualWidth >= comboBox.ActualWidth * 0.6
                    && border.ActualHeight >= comboBox.ActualHeight * 0.6)
                {
                    border.Background = surface;
                    border.BorderBrush = separator;
                }
            }
        }

        private void HookAndRefreshItems()
        {
            for (var index = 0; index < comboBox.Items.Count; index++)
            {
                if (comboBox.ItemContainerGenerator.ContainerFromIndex(index)
                    is not ComboBoxItem item)
                {
                    continue;
                }

                if (hookedItems.Add(item))
                {
                    item.Selected += ItemStateChanged;
                    item.Unselected += ItemStateChanged;
                    item.MouseEnter += ItemMouseStateChanged;
                    item.MouseLeave += ItemMouseStateChanged;
                    item.IsEnabledChanged += ItemStateChanged;
                    highlightedDescriptor?.AddValueChanged(item, ItemHighlightedChanged);
                }

                RefreshItem(item);
            }
        }

        private void UnhookItems()
        {
            foreach (var item in hookedItems)
            {
                item.Selected -= ItemStateChanged;
                item.Unselected -= ItemStateChanged;
                item.MouseEnter -= ItemMouseStateChanged;
                item.MouseLeave -= ItemMouseStateChanged;
                item.IsEnabledChanged -= ItemStateChanged;
                highlightedDescriptor?.RemoveValueChanged(item, ItemHighlightedChanged);
            }
            hookedItems.Clear();
        }

        private void ItemStateChanged(object sender, RoutedEventArgs eventArgs)
        {
            if (sender is ComboBoxItem item)
            {
                ScheduleItemRefresh(item);
            }
        }

        private void ItemStateChanged(object sender, DependencyPropertyChangedEventArgs eventArgs)
        {
            if (sender is ComboBoxItem item)
            {
                ScheduleItemRefresh(item);
            }
        }

        private void ItemMouseStateChanged(object sender, System.Windows.Input.MouseEventArgs eventArgs)
        {
            if (sender is ComboBoxItem item)
            {
                ScheduleItemRefresh(item);
            }
        }

        private void ItemHighlightedChanged(object? sender, EventArgs eventArgs)
        {
            if (sender is ComboBoxItem item)
            {
                ScheduleItemRefresh(item);
            }
        }

        private void ScheduleItemRefresh(ComboBoxItem item)
        {
            if (!item.Dispatcher.HasShutdownStarted)
            {
                _ = item.Dispatcher.BeginInvoke(
                    DispatcherPriority.Render,
                    () => RefreshItem(item));
            }
        }

        private void RefreshItem(ComboBoxItem item)
        {
            var selected = item.IsSelected;
            var highlighted = item.IsHighlighted || item.IsMouseOver;
            var background = selected && highlighted
                ? ResourceBrush(comboBox, "ComboBoxItem.ItemsviewSelectedHover.Background", FallbackSelectedHover)
                : selected
                    ? ResourceBrush(comboBox, "ComboBoxItem.ItemsviewSelected.Background", FallbackSelected)
                    : highlighted
                        ? ResourceBrush(comboBox, "ComboBoxItem.ItemsviewHover.Background", FallbackHover)
                        : Brushes.Transparent;
            var borderBrush = selected
                ? ResourceBrush(comboBox, "ComboBoxItem.ItemsviewSelected.Border", FallbackAccent)
                : highlighted
                    ? ResourceBrush(comboBox, "ComboBoxItem.ItemsviewHover.Border", FallbackSelected)
                    : Brushes.Transparent;

            item.Background = background;
            item.BorderBrush = borderBrush;
            item.Foreground = item.IsEnabled
                ? FallbackPrimary
                : ResourceBrush(comboBox, "ComboBox.Disabled.Foreground", FallbackPrimary);

            var borders = Descendants<Border>(item).ToArray();
            if (borders.Length == 0)
            {
                return;
            }

            // The native theme's selected/hover overlay is the largest Border
            // inside the container. A local brush has higher precedence than the
            // theme trigger while preserving all native hit testing and selection.
            var chrome = borders
                .OrderByDescending(border => border.ActualWidth * border.ActualHeight)
                .First();
            chrome.Background = background;
            chrome.BorderBrush = borderBrush;
        }
    }
}
