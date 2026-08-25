using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Threading;
using Battuta.Core.Audio;
using Battuta.TestSupport;
using Battuta.TestSupport.Threading;
using Battuta.Windows.Views.Tray;

namespace Battuta.Windows.Tests.Ui;

public sealed class TrayComboBoxInteractionTests
{
    private const uint InputKeyboard = 1;
    private const ushort VirtualKeyMenu = 0x12;
    private const ushort VirtualKeyDown = 0x28;
    private const uint KeyEventKeyUp = 0x0002;
    private const uint MouseEventMove = 0x0001;
    private const uint MouseEventLeftDown = 0x0002;
    private const uint MouseEventLeftUp = 0x0004;
    private const uint MouseEventVirtualDesk = 0x4000;
    private const uint MouseEventAbsolute = 0x8000;
    private const int SystemMetricVirtualScreenX = 76;
    private const int SystemMetricVirtualScreenY = 77;
    private const int SystemMetricVirtualScreenWidth = 78;
    private const int SystemMetricVirtualScreenHeight = 79;

    [Theory]
    [InlineData("KeyboardProfileCombo", 20)]
    [InlineData("PointerProfileCombo", 5)]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public async Task ShownTrayProfileComboExpandsKeyboardSelectsAndThenDismissesOnExternalFocus(
        string comboBoxName,
        int minimumItemCount)
    {
        await StaTestHost.RunAsync(async () =>
        {
            var flyout = CreateFlyoutWithProductionCatalogs();
            var focusSink = CreateInvisibleWindow();
            try
            {
                flyout.Show();
                flyout.ActivateFromTray();
                PumpDispatcherFor(TimeSpan.FromMilliseconds(100));

                var comboBox = Assert.IsType<ComboBox>(flyout.FindName(comboBoxName));
                Assert.True(comboBox.IsEnabled);
                Assert.True(comboBox.Items.Count >= minimumItemCount);
                Assert.Equal(0, comboBox.SelectedIndex);
                _ = comboBox.ApplyTemplate();
                comboBox.UpdateLayout();

                var popup = Assert.IsType<Popup>(
                    comboBox.Template.FindName("PART_Popup", comboBox));
                var popupChild = Assert.IsAssignableFrom<FrameworkElement>(popup.Child);
                // The popup still owns a real presentation HWND and participates in
                // layout, but stays transparent so this automated test cannot flash
                // over the user's desktop.
                popupChild.Opacity = 0;

                var expandCollapse = Assert.IsAssignableFrom<IExpandCollapseProvider>(
                    new ComboBoxAutomationPeer(comboBox)
                        .GetPattern(PatternInterface.ExpandCollapse));
                expandCollapse.Expand();
                PumpDispatcherFor(TimeSpan.FromMilliseconds(100));

                Assert.True(comboBox.IsDropDownOpen);
                Assert.True(popup.IsOpen);
                Assert.True(popupChild.IsVisible);
                Assert.True(popupChild.ActualWidth > 0);
                Assert.True(popupChild.ActualHeight > 0);
                Assert.True(flyout.IsVisible);

                var selectionChanges = 0;
                var originalSelectedValue = comboBox.SelectedValue;
                comboBox.SelectionChanged += (_, _) => selectionChanges++;
                Assert.True(comboBox.Focus());
                RaiseKeyDown(comboBox, Key.Down);
                RaiseKeyDown(comboBox, Key.Enter);
                PumpDispatcherFor(TimeSpan.FromMilliseconds(100));

                Assert.Equal(1, comboBox.SelectedIndex);
                Assert.NotEqual(originalSelectedValue, comboBox.SelectedValue);
                Assert.Equal(1, selectionChanges);
                Assert.False(comboBox.IsDropDownOpen);
                Assert.False(popup.IsOpen);
                Assert.True(flyout.IsVisible);

                focusSink.Show();
                _ = focusSink.Activate();
                _ = focusSink.Focus();
                PumpDispatcherFor(TimeSpan.FromMilliseconds(100));

                // Wait past the maximum open-popup suppression interval. An
                // implementation may dismiss sooner after the popup has closed,
                // but it must never leave a zombie flyout behind.
                await Task.Delay(TimeSpan.FromMilliseconds(1_050));
                PumpDispatcherFor(TimeSpan.FromMilliseconds(100));
                Assert.False(flyout.IsVisible);
            }
            finally
            {
                if (focusSink.IsVisible)
                {
                    focusSink.Close();
                }

                flyout.Close();
                flyout.Dispose();
            }
        });
    }

    [Theory]
    [InlineData("KeyboardProfileCombo", 20)]
    [InlineData("PointerProfileCombo", 5)]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void ShownTrayProfileComboMouseClickCommitsSecondItemAndClosesDropDown(
        string comboBoxName,
        int minimumItemCount)
    {
        StaTestHost.Run(() =>
        {
            var flyout = CreateFlyoutWithProductionCatalogs();
            try
            {
                flyout.Show();
                flyout.ActivateFromTray();
                PumpDispatcherFor(TimeSpan.FromMilliseconds(100));

                var comboBox = Assert.IsType<ComboBox>(flyout.FindName(comboBoxName));
                Assert.True(comboBox.Items.Count >= minimumItemCount);
                _ = comboBox.ApplyTemplate();
                var popup = Assert.IsType<Popup>(
                    comboBox.Template.FindName("PART_Popup", comboBox));
                var popupChild = Assert.IsAssignableFrom<FrameworkElement>(popup.Child);
                popupChild.Opacity = 0;
                var expandCollapse = Assert.IsAssignableFrom<IExpandCollapseProvider>(
                    new ComboBoxAutomationPeer(comboBox)
                        .GetPattern(PatternInterface.ExpandCollapse));
                expandCollapse.Expand();
                PumpDispatcherFor(TimeSpan.FromMilliseconds(100));

                var originalSelectedValue = comboBox.SelectedValue;
                var selectionChanges = 0;
                comboBox.SelectionChanged += (_, _) => selectionChanges++;
                var secondItem = Assert.IsType<ComboBoxItem>(
                    comboBox.ItemContainerGenerator.ContainerFromIndex(1));
                Assert.True(secondItem.IsVisible);
                RaisePopupPreviewMouseUp(popupChild, secondItem);
                PumpDispatcherFor(TimeSpan.FromMilliseconds(100));

                Assert.Equal(1, comboBox.SelectedIndex);
                Assert.NotEqual(originalSelectedValue, comboBox.SelectedValue);
                Assert.Equal(1, selectionChanges);
                Assert.False(comboBox.IsDropDownOpen);
                Assert.False(popup.IsOpen);
                Assert.True(flyout.IsVisible);
            }
            finally
            {
                flyout.Close();
                flyout.Dispose();
            }
        });
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Integration)]
    public void RealMouseClickAndAltDownExpandShownTrayCombosWhenInteractiveTestingIsEnabled()
    {
        StaTestHost.Run(() =>
        {
            if (!string.Equals(
                    Environment.GetEnvironmentVariable("BATTUTA_REQUIRE_INTERACTIVE_TRAY_TEST"),
                    "1",
                    StringComparison.Ordinal))
            {
                return;
            }

            if (!Environment.UserInteractive || !GetCursorPosition(out var originalCursor))
            {
                Assert.Skip("The interactive tray test cannot access a user input desktop.");
                return;
            }

            var flyout = CreateFlyoutWithProductionCatalogs(interactive: true);
            try
            {
                flyout.Show();
                flyout.ActivateFromTray();
                PumpDispatcherFor(TimeSpan.FromMilliseconds(100));

                var keyboardCombo = Assert.IsType<ComboBox>(
                    flyout.FindName("KeyboardProfileCombo"));
                _ = keyboardCombo.ApplyTemplate();
                var keyboardPopup = Assert.IsType<Popup>(
                    keyboardCombo.Template.FindName("PART_Popup", keyboardCombo));
                Assert.IsAssignableFrom<FrameworkElement>(keyboardPopup.Child).Opacity = 0;
                var comboCenter = keyboardCombo.PointToScreen(new Point(
                    keyboardCombo.ActualWidth / 2,
                    keyboardCombo.ActualHeight / 2));
                if (!SendAbsoluteMouseMove((int)comboCenter.X, (int)comboCenter.Y))
                {
                    Assert.Skip("SendInput could not move the cursor on this input desktop.");
                    return;
                }

                PumpDispatcherFor(TimeSpan.FromMilliseconds(50));
                var reachedCombo = CursorIsNear(comboCenter, out var movedCursor);
                if (!reachedCombo)
                {
                    _ = SetCursorPosition((int)comboCenter.X, (int)comboCenter.Y);
                    PumpDispatcherFor(TimeSpan.FromMilliseconds(50));
                    reachedCombo = CursorIsNear(comboCenter, out movedCursor);
                }

                if (!reachedCombo)
                {
                    Assert.Skip(
                        $"SendInput could not reach the ComboBox at "
                        + $"[{comboCenter.X:N0},{comboCenter.Y:N0}]; cursor reached "
                        + $"[{movedCursor.X},{movedCursor.Y}] on this input desktop.");
                    return;
                }

                Assert.Equal(
                    2u,
                    SendInputNative(
                        2,
                        [
                            NativeInput.Mouse(MouseEventLeftDown),
                            NativeInput.Mouse(MouseEventLeftUp),
                        ],
                        Marshal.SizeOf<NativeInput>()));
                PumpDispatcherFor(TimeSpan.FromMilliseconds(150));

                Assert.True(keyboardCombo.IsDropDownOpen);
                Assert.True(keyboardPopup.IsOpen);
                Assert.True(keyboardPopup.Child?.IsVisible);
                Assert.True(flyout.IsVisible);

                var keyboardExpandCollapse = Assert.IsAssignableFrom<IExpandCollapseProvider>(
                    new ComboBoxAutomationPeer(keyboardCombo)
                        .GetPattern(PatternInterface.ExpandCollapse));
                keyboardExpandCollapse.Collapse();
                PumpDispatcherFor(TimeSpan.FromMilliseconds(100));

                var pointerCombo = Assert.IsType<ComboBox>(
                    flyout.FindName("PointerProfileCombo"));
                _ = pointerCombo.ApplyTemplate();
                var pointerPopup = Assert.IsType<Popup>(
                    pointerCombo.Template.FindName("PART_Popup", pointerCombo));
                Assert.IsAssignableFrom<FrameworkElement>(pointerPopup.Child).Opacity = 0;
                Assert.True(pointerCombo.Focus());
                PumpDispatcherFor(TimeSpan.FromMilliseconds(50));

                NativeInput[] input =
                [
                    NativeInput.Key(VirtualKeyMenu),
                    NativeInput.Key(VirtualKeyDown),
                    NativeInput.Key(VirtualKeyDown, KeyEventKeyUp),
                    NativeInput.Key(VirtualKeyMenu, KeyEventKeyUp),
                ];
                Assert.Equal(
                    (uint)input.Length,
                    SendInputNative((uint)input.Length, input, Marshal.SizeOf<NativeInput>()));
                PumpDispatcherFor(TimeSpan.FromMilliseconds(150));

                Assert.True(pointerCombo.IsDropDownOpen);
                Assert.True(pointerPopup.IsOpen);
                Assert.True(pointerPopup.Child?.IsVisible);
                Assert.True(flyout.IsVisible);
            }
            finally
            {
                _ = SetCursorPosition(originalCursor.X, originalCursor.Y);
                flyout.Close();
                flyout.Dispose();
            }
        });
    }

    private static TrayFlyoutWindow CreateFlyoutWithProductionCatalogs(bool interactive = false)
    {
        var flyout = new TrayFlyoutWindow
        {
            Left = interactive ? 80 : -32_000,
            Top = interactive ? 80 : -32_000,
            Opacity = interactive ? 0.02 : 0,
            ShowActivated = interactive,
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

    private static Window CreateInvisibleWindow() => new()
    {
        Left = -32_000,
        Top = -32_000,
        Width = 80,
        Height = 80,
        Opacity = 0,
        ShowInTaskbar = false,
        WindowStyle = WindowStyle.None,
    };

    private static void RaiseKeyDown(UIElement target, Key key)
    {
        var source = PresentationSource.FromVisual(target)
            ?? throw new InvalidOperationException("The shown ComboBox has no presentation source.");
        target.RaiseEvent(new KeyEventArgs(
            Keyboard.PrimaryDevice,
            source,
            Environment.TickCount,
            key)
        {
            RoutedEvent = Keyboard.KeyDownEvent,
        });
    }

    private static void RaisePopupPreviewMouseUp(
        UIElement popupChild,
        ComboBoxItem item)
    {
        _ = PresentationSource.FromVisual(popupChild)
            ?? throw new InvalidOperationException("The shown ComboBoxItem has no presentation source.");
        var itemCenter = item.TranslatePoint(
            new Point(item.ActualWidth / 2, item.ActualHeight / 2),
            popupChild);
        var hitTarget = Assert.IsAssignableFrom<IInputElement>(
            popupChild.InputHitTest(itemCenter));
        Assert.NotSame(item, hitTarget);
        var previewMouseUp = new MouseButtonEventArgs(
            Mouse.PrimaryDevice,
            Environment.TickCount,
            MouseButton.Left)
        {
            RoutedEvent = UIElement.PreviewMouseLeftButtonUpEvent,
            Source = hitTarget,
        };
        popupChild.RaiseEvent(previewMouseUp);
        Assert.True(previewMouseUp.Handled);
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

    private static bool SendAbsoluteMouseMove(int x, int y)
    {
        var previousDpiContext = SetThreadDpiAwarenessContext(new IntPtr(-4));
        int left;
        int top;
        int width;
        int height;
        try
        {
            left = GetSystemMetrics(SystemMetricVirtualScreenX);
            top = GetSystemMetrics(SystemMetricVirtualScreenY);
            width = GetSystemMetrics(SystemMetricVirtualScreenWidth);
            height = GetSystemMetrics(SystemMetricVirtualScreenHeight);
        }
        finally
        {
            if (previousDpiContext != IntPtr.Zero)
            {
                _ = SetThreadDpiAwarenessContext(previousDpiContext);
            }
        }

        if (width <= 1 || height <= 1)
        {
            return false;
        }

        var normalizedX = checked((int)Math.Round(
            (Math.Clamp(x, left, left + width - 1) - left) * 65_535d / (width - 1)));
        var normalizedY = checked((int)Math.Round(
            (Math.Clamp(y, top, top + height - 1) - top) * 65_535d / (height - 1)));
        NativeInput[] input =
        [
            NativeInput.Mouse(
                MouseEventMove | MouseEventAbsolute | MouseEventVirtualDesk,
                normalizedX,
                normalizedY),
        ];
        return SendInputNative(1, input, Marshal.SizeOf<NativeInput>()) == 1;
    }

    private static bool CursorIsNear(Point target, out NativePoint cursor) =>
        GetCursorPosition(out cursor)
        && Math.Abs(cursor.X - target.X) <= 3
        && Math.Abs(cursor.Y - target.Y) <= 3;

    [DllImport("user32.dll", EntryPoint = "SendInput", SetLastError = true)]
    private static extern uint SendInputNative(
        uint inputCount,
        [In] NativeInput[] inputs,
        int inputSize);

    [DllImport("user32.dll", EntryPoint = "GetCursorPos", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPosition(out NativePoint point);

    [DllImport("user32.dll", EntryPoint = "SetCursorPos", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetCursorPosition(int x, int y);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll")]
    private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeInput
    {
        public uint Type;
        public NativeInputUnion Data;

        public static NativeInput Key(ushort virtualKey, uint flags = 0) => new()
        {
            Type = InputKeyboard,
            Data = new NativeInputUnion
            {
                Keyboard = new NativeKeyboardInput
                {
                    VirtualKey = virtualKey,
                    Flags = flags,
                },
            },
        };

        public static NativeInput Mouse(uint flags, int x = 0, int y = 0) => new()
        {
            Type = 0,
            Data = new NativeInputUnion
            {
                Mouse = new NativeMouseInput
                {
                    X = x,
                    Y = y,
                    Flags = flags,
                },
            },
        };
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct NativeInputUnion
    {
        [FieldOffset(0)]
        public NativeMouseInput Mouse;

        [FieldOffset(0)]
        public NativeKeyboardInput Keyboard;

        [FieldOffset(0)]
        public NativeHardwareInput Hardware;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeMouseInput
    {
        public int X;
        public int Y;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public UIntPtr ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeKeyboardInput
    {
        public ushort VirtualKey;
        public ushort ScanCode;
        public uint Flags;
        public uint Time;
        public UIntPtr ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeHardwareInput
    {
        public uint Message;
        public ushort ParameterLow;
        public ushort ParameterHigh;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }
}
