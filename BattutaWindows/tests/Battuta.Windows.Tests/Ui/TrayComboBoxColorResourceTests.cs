using System.Windows;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Threading;
using Battuta.Core.Audio;
using Battuta.TestSupport;
using Battuta.TestSupport.Threading;
using Battuta.Windows.Views.Tray;

namespace Battuta.Windows.Tests.Ui;

public sealed class TrayComboBoxColorResourceTests
{
    private static readonly string[] EditableComboStates = ["Static", "MouseOver", "Pressed"];

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void NativeComboStylesKeepSystemTemplatesAndDefineDistinctDarkStateResources()
    {
        StaTestHost.Run(() =>
        {
            using var flyout = new TrayFlyoutWindow();
            var comboStyle = Assert.IsType<Style>(flyout.FindResource("Battuta.ComboBox"));
            var itemStyle = Assert.IsType<Style>(flyout.FindResource(typeof(ComboBoxItem)));

            Assert.DoesNotContain(
                comboStyle.Setters.OfType<Setter>(),
                setter => setter.Property == Control.TemplateProperty);
            Assert.DoesNotContain(
                itemStyle.Setters.OfType<Setter>(),
                setter => setter.Property == Control.TemplateProperty);

            var popup = ResourceColor(comboStyle, SystemColors.WindowBrushKey);
            var popupText = ResourceColor(comboStyle, SystemColors.WindowTextBrushKey);
            var selected = ResourceColor(comboStyle, SystemColors.HighlightBrushKey);
            var selectedText = ResourceColor(comboStyle, SystemColors.HighlightTextBrushKey);
            var inactiveSelected = ResourceColor(
                comboStyle,
                SystemColors.InactiveSelectionHighlightBrushKey);
            var hoverSystemColor = ResourceColor(comboStyle, SystemColors.HotTrackBrushKey);

            AssertDark(popup);
            Assert.NotEqual(Colors.White, popup);
            Assert.True(ContrastRatio(popupText, popup) >= 4.5);
            Assert.True(ContrastRatio(selectedText, selected) >= 4.5);
            Assert.NotEqual(popup, selected);
            Assert.NotEqual(selected, inactiveSelected);
            Assert.NotEqual(selected, hoverSystemColor);

            var staticBackground = AssertStateResources(
                comboStyle,
                "ComboBox.Static.Background",
                "ComboBox.Static.Border");
            var mouseOverBackground = AssertStateResources(
                comboStyle,
                "ComboBox.MouseOver.Background",
                "ComboBox.MouseOver.Border");
            var pressedBackground = AssertStateResources(
                comboStyle,
                "ComboBox.Pressed.Background",
                "ComboBox.Pressed.Border");
            _ = AssertStateResources(
                comboStyle,
                "ComboBox.Disabled.Background",
                "ComboBox.Disabled.Border",
                "ComboBox.Disabled.Foreground");
            AssertDark(staticBackground);
            AssertDark(mouseOverBackground);
            AssertDark(pressedBackground);
            AssertNotSystemWhiteOrBlue(staticBackground);
            AssertNotSystemWhiteOrBlue(mouseOverBackground);
            AssertNotSystemWhiteOrBlue(pressedBackground);
            Assert.NotEqual(staticBackground, mouseOverBackground);
            Assert.NotEqual(mouseOverBackground, pressedBackground);

            foreach (var editableState in EditableComboStates)
            {
                _ = AssertStateResources(
                    comboStyle,
                    $"ComboBox.{editableState}.Editable.Background",
                    $"ComboBox.{editableState}.Editable.Border",
                    $"ComboBox.{editableState}.Editable.Button.Background",
                    $"ComboBox.{editableState}.Editable.Button.Border");
            }

            var itemHover = AssertStateResources(
                itemStyle,
                "ComboBoxItem.ItemsviewHover.Background",
                "ComboBoxItem.ItemsviewHover.Border");
            var itemSelected = AssertStateResources(
                itemStyle,
                "ComboBoxItem.ItemsviewSelected.Background",
                "ComboBoxItem.ItemsviewSelected.Border");
            var itemSelectedHover = AssertStateResources(
                itemStyle,
                "ComboBoxItem.ItemsviewSelectedHover.Background",
                "ComboBoxItem.ItemsviewSelectedHover.Border");
            var itemSelectedInactive = AssertStateResources(
                itemStyle,
                "ComboBoxItem.ItemsviewSelectedInactive.Background",
                "ComboBoxItem.ItemsviewSelectedInactive.Border");
            foreach (var state in new[]
            {
                itemHover,
                itemSelected,
                itemSelectedHover,
                itemSelectedInactive,
            })
            {
                AssertDark(state);
                AssertNotSystemWhiteOrBlue(state);
            }

            Assert.Equal(4, new HashSet<Color>
            {
                itemHover,
                itemSelected,
                itemSelectedHover,
                itemSelectedInactive,
            }.Count);

            var highlightedTrigger = Assert.Single(
                itemStyle.Triggers.OfType<Trigger>(),
                trigger => trigger.Property == ComboBoxItem.IsHighlightedProperty
                    && Equals(trigger.Value, true));
            var hover = Assert.IsType<SolidColorBrush>(
                Assert.Single(
                    highlightedTrigger.Setters.OfType<Setter>(),
                    setter => setter.Property == Control.BackgroundProperty).Value).Color;
            Assert.NotEqual(hover, selected);
            Assert.NotEqual(hover, popup);
        });
    }

    [Theory]
    [InlineData("KeyboardProfileCombo", 20)]
    [InlineData("PointerProfileCombo", 5)]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void ShownNativePopupIsDarkReadableAndEveryCatalogItemCanBeBroughtIntoView(
        string comboBoxName,
        int expectedItemCount)
    {
        StaTestHost.Run(() =>
        {
            using var flyout = CreateFlyoutWithProductionCatalogs();
            try
            {
                flyout.Show();
                flyout.ActivateFromTray();
                PumpDispatcherFor(TimeSpan.FromMilliseconds(100));

                var comboBox = Assert.IsType<ComboBox>(flyout.FindName(comboBoxName));
                Assert.Equal(expectedItemCount, comboBox.Items.Count);
                _ = comboBox.ApplyTemplate();
                comboBox.UpdateLayout();
                var closedBackground = FindPresentedBackground(
                    comboBox,
                    includeRoot: false);
                AssertDark(closedBackground);
                AssertNotSystemWhiteOrBlue(closedBackground);
                var popup = Assert.IsType<Popup>(
                    comboBox.Template.FindName("PART_Popup", comboBox));
                var popupChild = Assert.IsAssignableFrom<FrameworkElement>(popup.Child);
                var expandCollapse = Assert.IsAssignableFrom<IExpandCollapseProvider>(
                    new ComboBoxAutomationPeer(comboBox)
                        .GetPattern(PatternInterface.ExpandCollapse));
                expandCollapse.Expand();
                PumpDispatcherFor(TimeSpan.FromMilliseconds(100));

                Assert.True(popup.IsOpen);
                Assert.True(popupChild.IsVisible);
                var popupBackground = FindPresentedBackground(
                    popupChild,
                    includeRoot: true);
                AssertDark(popupBackground);
                Assert.NotEqual(Colors.White, popupBackground);
                if (RelativeLuminance(SystemColors.WindowColor) > 0.8)
                {
                    Assert.NotEqual(SystemColors.WindowColor, popupBackground);
                }

                var normalItem = GetVisibleContainer(comboBox, popupChild, 1);
                Assert.False(normalItem.IsSelected);
                Assert.False(normalItem.IsHighlighted);
                var foreground = Assert.IsType<SolidColorBrush>(normalItem.Foreground).Color;
                var effectiveBackground = normalItem.Background is SolidColorBrush itemBackground
                    && itemBackground.Color.A > 0
                        ? itemBackground.Color
                        : popupBackground;
                Assert.True(
                    ContrastRatio(foreground, effectiveBackground) >= 4.5,
                    $"Normal item contrast was only "
                    + $"{ContrastRatio(foreground, effectiveBackground):N2}:1.");

                var hover = HighlightedItemColor(comboBox);
                comboBox.SelectedIndex = 1;
                PumpDispatcherFor(TimeSpan.FromMilliseconds(50));
                var selectedItem = GetVisibleContainer(comboBox, popupChild, 1);
                var selectedBackground = Assert.IsType<SolidColorBrush>(selectedItem.Background).Color;
                var presentedSelectedBackground = FindPresentedBackground(
                    selectedItem,
                    includeRoot: false);
                Assert.NotEqual(hover, selectedBackground);
                Assert.NotEqual(popupBackground, selectedBackground);
                AssertDark(presentedSelectedBackground);
                AssertNotSystemWhiteOrBlue(presentedSelectedBackground);

                for (var index = 0; index < expectedItemCount; index++)
                {
                    var item = GetVisibleContainer(comboBox, popupChild, index);
                    Assert.Equal(Visibility.Visible, item.Visibility);
                    Assert.True(item.IsVisible);
                    Assert.True(item.ActualWidth > 0);
                    Assert.True(item.ActualHeight > 0);
                    Assert.False(string.IsNullOrWhiteSpace(comboBox.Items[index]?.ToString()));

                    var origin = item.TranslatePoint(new Point(), popupChild);
                    var itemBounds = new Rect(origin, item.RenderSize);
                    Assert.True(
                        itemBounds.IntersectsWith(new Rect(new Point(), popupChild.RenderSize)),
                        $"Item {index} was not visible inside the open Popup viewport.");
                }

                Assert.True(flyout.IsVisible);
            }
            finally
            {
                flyout.Close();
            }
        });
    }

    private static TrayFlyoutWindow CreateFlyoutWithProductionCatalogs()
    {
        var flyout = new TrayFlyoutWindow
        {
            Left = -32_000,
            Top = -32_000,
            Opacity = 0,
            ShowActivated = false,
        };
        SetItems(
            Assert.IsType<ComboBox>(flyout.FindName("KeyboardProfileCombo")),
            SwitchProfileCatalog.All.Select(profile => profile.DisplayName));
        SetItems(
            Assert.IsType<ComboBox>(flyout.FindName("PointerProfileCombo")),
            PointerSoundProfileCatalog.All.Select(profile => profile.DisplayName));
        return flyout;
    }

    private static void SetItems(ComboBox comboBox, IEnumerable<string> items)
    {
        comboBox.ItemsSource = null;
        comboBox.Items.Clear();
        comboBox.ItemsSource = items.ToArray();
        comboBox.SelectedIndex = 0;
    }

    private static ComboBoxItem GetVisibleContainer(
        ComboBox comboBox,
        FrameworkElement popupChild,
        int index)
    {
        var scrollViewer = VisualDescendants<ScrollViewer>(popupChild).FirstOrDefault();
        for (var attempt = 0; attempt < 3; attempt++)
        {
            if (comboBox.ItemContainerGenerator.ContainerFromIndex(index) is ComboBoxItem item)
            {
                item.BringIntoView();
                PumpDispatcherFor(TimeSpan.FromMilliseconds(20));
                return item;
            }

            scrollViewer?.ScrollToVerticalOffset(
                scrollViewer.CanContentScroll ? index : index * 32d);
            PumpDispatcherFor(TimeSpan.FromMilliseconds(20));
        }

        return Assert.IsType<ComboBoxItem>(
            comboBox.ItemContainerGenerator.ContainerFromIndex(index));
    }

    private static Color FindPresentedBackground(
        FrameworkElement root,
        bool includeRoot)
    {
        var candidate = VisualDescendants<FrameworkElement>(root, includeRoot)
            .Select(element => (Element: element, Brush: ElementBackground(element)))
            .Where(item => item.Brush is SolidColorBrush { Color.A: > 0 })
            .OrderByDescending(item => item.Element.ActualWidth * item.Element.ActualHeight)
            .FirstOrDefault();
        var brush = Assert.IsType<SolidColorBrush>(candidate.Brush);
        Assert.True(
            candidate.Element.ActualWidth * candidate.Element.ActualHeight
                >= root.ActualWidth * root.ActualHeight * 0.5);
        return brush.Color;
    }

    private static Brush? ElementBackground(FrameworkElement element) => element switch
    {
        Border border => border.Background,
        Panel panel => panel.Background,
        Control control => control.Background,
        TextBlock text => text.Background,
        _ => null,
    };

    private static Color HighlightedItemColor(ComboBox comboBox)
    {
        var itemStyle = Assert.IsType<Style>(comboBox.FindResource(typeof(ComboBoxItem)));
        var trigger = Assert.Single(
            itemStyle.Triggers.OfType<Trigger>(),
            candidate => candidate.Property == ComboBoxItem.IsHighlightedProperty
                && Equals(candidate.Value, true));
        return Assert.IsType<SolidColorBrush>(
            Assert.Single(
                trigger.Setters.OfType<Setter>(),
                setter => setter.Property == Control.BackgroundProperty).Value).Color;
    }

    private static Color ResourceColor(Style style, object key) =>
        Assert.IsType<SolidColorBrush>(style.Resources[key]).Color;

    private static Color AssertStateResources(
        Style style,
        string backgroundKey,
        params string[] additionalKeys)
    {
        Assert.True(style.Resources.Contains(backgroundKey));
        var background = ResourceColor(style, backgroundKey);
        foreach (var key in additionalKeys)
        {
            Assert.True(style.Resources.Contains(key), $"Missing native theme resource '{key}'.");
            var color = ResourceColor(style, key);
            Assert.NotEqual(SystemColors.HighlightColor, color);
        }

        return background;
    }

    private static void AssertNotSystemWhiteOrBlue(Color color)
    {
        Assert.NotEqual(Colors.White, color);
        Assert.NotEqual(SystemColors.WindowColor, color);
        Assert.NotEqual(SystemColors.HighlightColor, color);
        Assert.False(
            color.B > color.R * 1.2 && color.B > color.G * 1.2,
            $"Expected a Battuta neutral/green color, got system-like blue {color}.");
    }

    private static void AssertDark(Color color) =>
        Assert.True(
            RelativeLuminance(color) < 0.25,
            $"Expected a dark Popup color, got {color}.");

    private static double ContrastRatio(Color foreground, Color background)
    {
        var opaqueBackground = Composite(background, Colors.Black);
        var opaqueForeground = Composite(foreground, opaqueBackground);
        var lighter = Math.Max(
            RelativeLuminance(opaqueForeground),
            RelativeLuminance(opaqueBackground));
        var darker = Math.Min(
            RelativeLuminance(opaqueForeground),
            RelativeLuminance(opaqueBackground));
        return (lighter + 0.05) / (darker + 0.05);
    }

    private static Color Composite(Color foreground, Color background)
    {
        var alpha = foreground.A / 255d;
        return Color.FromRgb(
            (byte)Math.Round(foreground.R * alpha + background.R * (1 - alpha)),
            (byte)Math.Round(foreground.G * alpha + background.G * (1 - alpha)),
            (byte)Math.Round(foreground.B * alpha + background.B * (1 - alpha)));
    }

    private static double RelativeLuminance(Color color)
    {
        static double Channel(byte value)
        {
            var normalized = value / 255d;
            return normalized <= 0.04045
                ? normalized / 12.92
                : Math.Pow((normalized + 0.055) / 1.055, 2.4);
        }

        return 0.2126 * Channel(color.R)
            + 0.7152 * Channel(color.G)
            + 0.0722 * Channel(color.B);
    }

    private static IEnumerable<T> VisualDescendants<T>(
        DependencyObject root,
        bool includeRoot = false)
        where T : DependencyObject
    {
        if (includeRoot && root is T rootMatch)
        {
            yield return rootMatch;
        }

        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            if (child is T match)
            {
                yield return match;
            }

            foreach (var descendant in VisualDescendants<T>(child))
            {
                yield return descendant;
            }
        }
    }

    private static void PumpDispatcherFor(TimeSpan duration)
    {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer(
            duration,
            DispatcherPriority.Background,
            (_, _) => frame.Continue = false,
            Dispatcher.CurrentDispatcher);
        timer.Start();
        Dispatcher.PushFrame(frame);
        timer.Stop();
    }
}
