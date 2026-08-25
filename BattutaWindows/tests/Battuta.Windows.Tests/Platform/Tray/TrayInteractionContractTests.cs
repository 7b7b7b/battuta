using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Threading;
using Battuta.TestSupport;
using Battuta.TestSupport.Threading;
using Battuta.Windows.Tray;
using Battuta.Windows.Views.Tray;

namespace Battuta.Windows.Tests.Platform.Tray;

public sealed class TrayInteractionContractTests
{
    private const int CallbackMessage = 0x8001;
    private const int WmContextMenu = 0x007B;
    private const int WmLButtonUp = 0x0202;
    private const int WmRButtonUp = 0x0205;
    private const int NinSelect = 0x0400;

    [Theory]
    [InlineData(WmLButtonUp)]
    [InlineData(NinSelect)]
    [Trait(TestCategories.TraitName, TestCategories.Integration)]
    public void EitherPrimaryNotificationAloneProducesOneInvocation(int notification)
    {
        StaTestHost.Run(() =>
        {
            using var service = CreateTrayIconService();
            var observed = new List<TrayIconInvocation>();
            service.Invoked += (_, eventArgs) => observed.Add(eventArgs.Invocation);

            Assert.True(DispatchNotification(service, notification, PackPoint(240, 180)));

            Assert.Equal([TrayIconInvocation.Primary], observed);
        });
    }

    [Theory]
    [InlineData(WmLButtonUp, NinSelect)]
    [InlineData(NinSelect, WmLButtonUp)]
    [Trait(TestCategories.TraitName, TestCategories.Integration)]
    public void PartnerPrimaryNotificationsInsideWindowAreDeduplicated(
        int first,
        int second)
    {
        StaTestHost.Run(() =>
        {
            var time = new ManualTimeProvider();
            using var service = CreateTrayIconService(time);
            var observed = new List<TrayIconInvocation>();
            service.Invoked += (_, eventArgs) => observed.Add(eventArgs.Invocation);

            Assert.True(DispatchNotification(service, first, PackPoint(240, 180)));
            time.Advance(TimeSpan.FromMilliseconds(20));
            Assert.True(DispatchNotification(service, second, PackPoint(240, 180)));

            Assert.Equal([TrayIconInvocation.Primary], observed);
        });
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Integration)]
    public void PrimaryNotificationAfterDeduplicationWindowIsANewInvocation()
    {
        StaTestHost.Run(() =>
        {
            var time = new ManualTimeProvider();
            using var service = CreateTrayIconService(time);
            var primaryInvocations = 0;
            service.Invoked += (_, eventArgs) =>
                primaryInvocations += eventArgs.Invocation == TrayIconInvocation.Primary ? 1 : 0;

            Assert.True(DispatchNotification(service, WmLButtonUp, PackPoint(240, 180)));
            time.Advance(NativeTrayIconService.InvocationDeduplicationWindow + TimeSpan.FromMilliseconds(1));
            Assert.True(DispatchNotification(service, NinSelect, PackPoint(240, 180)));

            Assert.Equal(2, primaryInvocations);
        });
    }

    [Theory]
    [InlineData(WmRButtonUp)]
    [InlineData(WmContextMenu)]
    [Trait(TestCategories.TraitName, TestCategories.Integration)]
    public void EitherContextNotificationAloneProducesOneContextAndNoPrimary(int notification)
    {
        StaTestHost.Run(() =>
        {
            using var service = CreateTrayIconService();
            var observed = new List<TrayIconInvocation>();
            service.Invoked += (_, eventArgs) => observed.Add(eventArgs.Invocation);

            Assert.True(DispatchNotification(service, notification, PackPoint(240, 180)));

            Assert.Equal([TrayIconInvocation.ContextMenu], observed);
            Assert.DoesNotContain(TrayIconInvocation.Primary, observed);
        });
    }

    [Theory]
    [InlineData(WmRButtonUp, WmContextMenu)]
    [InlineData(WmContextMenu, WmRButtonUp)]
    [Trait(TestCategories.TraitName, TestCategories.Integration)]
    public void PartnerContextNotificationsInsideWindowAreDeduplicated(
        int first,
        int second)
    {
        StaTestHost.Run(() =>
        {
            var time = new ManualTimeProvider();
            using var service = CreateTrayIconService(time);
            var observed = new List<TrayIconInvocation>();
            service.Invoked += (_, eventArgs) => observed.Add(eventArgs.Invocation);

            Assert.True(DispatchNotification(service, first, PackPoint(240, 180)));
            time.Advance(TimeSpan.FromMilliseconds(20));
            Assert.True(DispatchNotification(service, second, PackPoint(240, 180)));

            Assert.Equal([TrayIconInvocation.ContextMenu], observed);
            Assert.DoesNotContain(TrayIconInvocation.Primary, observed);
        });
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Integration)]
    public void ContextNotificationAfterDeduplicationWindowIsANewInvocation()
    {
        StaTestHost.Run(() =>
        {
            var time = new ManualTimeProvider();
            using var service = CreateTrayIconService(time);
            var contextInvocations = 0;
            service.Invoked += (_, eventArgs) =>
                contextInvocations += eventArgs.Invocation == TrayIconInvocation.ContextMenu ? 1 : 0;

            Assert.True(DispatchNotification(service, WmRButtonUp, PackPoint(240, 180)));
            time.Advance(NativeTrayIconService.InvocationDeduplicationWindow + TimeSpan.FromMilliseconds(1));
            Assert.True(DispatchNotification(service, WmContextMenu, PackPoint(240, 180)));

            Assert.Equal(2, contextInvocations);
        });
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Integration)]
    public void ReentrantPartnerNotificationIsSuppressedWhileHandlerIsActive()
    {
        StaTestHost.Run(() =>
        {
            var time = new ManualTimeProvider();
            using var service = CreateTrayIconService(time);
            var primaryInvocations = 0;
            service.Invoked += (_, eventArgs) =>
            {
                if (eventArgs.Invocation != TrayIconInvocation.Primary)
                {
                    return;
                }

                primaryInvocations++;
                Assert.True(DispatchNotification(service, NinSelect, PackPoint(240, 180)));
            };

            Assert.True(DispatchNotification(service, WmLButtonUp, PackPoint(240, 180)));

            Assert.Equal(1, primaryInvocations);
        });
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Integration)]
    public void LongContextHandlerRefreshesDeadlineBeforeQueuedPartnerNotification()
    {
        StaTestHost.Run(() =>
        {
            var time = new ManualTimeProvider();
            using var service = CreateTrayIconService(time);
            var contextInvocations = 0;
            service.Invoked += (_, eventArgs) =>
            {
                if (eventArgs.Invocation == TrayIconInvocation.ContextMenu)
                {
                    contextInvocations++;
                    time.Advance(NativeTrayIconService.InvocationDeduplicationWindow * 2);
                }
            };

            Assert.True(DispatchNotification(service, WmRButtonUp, PackPoint(240, 180)));
            Assert.True(DispatchNotification(service, WmContextMenu, PackPoint(240, 180)));

            Assert.Equal(1, contextInvocations);
        });
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void TrayActivationCreatesAndRenewsAutoDismissSuppression()
    {
        StaTestHost.Run(() =>
        {
            var window = new TrayFlyoutWindow();
            try
            {
                window.Opacity = 0;
                window.ShowActivated = false;
                window.Left = -32_000;
                window.Top = -32_000;
                window.Show();

                var beforeFirstActivation = DateTime.UtcNow;
                window.ActivateFromTray();
                var firstDeadline = ReadSuppressionDeadline(window);
                Assert.InRange(
                    firstDeadline - beforeFirstActivation,
                    TimeSpan.FromMilliseconds(300),
                    TimeSpan.FromMilliseconds(900));

                Thread.Sleep(20);
                window.ActivateFromTray();
                var reopenedDeadline = ReadSuppressionDeadline(window);
                Assert.True(
                    reopenedDeadline > firstDeadline,
                    $"Expected reopening to renew suppression beyond {firstDeadline:O}, got {reopenedDeadline:O}.");
            }
            finally
            {
                window.Close();
            }
        });
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Integration)]
    public void NativeContextMenuRealOutsideClickReturnsNone()
    {
        StaTestHost.Run(() =>
        {
            var requireInteractive = string.Equals(
                Environment.GetEnvironmentVariable("BATTUTA_REQUIRE_INTERACTIVE_TRAY_TEST"),
                "1",
                StringComparison.Ordinal);
            if (!requireInteractive)
            {
                return;
            }

            if (!Environment.UserInteractive || !GetCursorPos(out var originalCursor))
            {
                Assert.Skip("The interactive tray test cannot access the user's input desktop.");
                return;
            }

            var owner = new Window
            {
                Left = 80,
                Top = 80,
                Width = 760,
                Height = 520,
                ShowInTaskbar = false,
                WindowStyle = WindowStyle.None,
                Opacity = 0.02,
            };
            using var trayService = CreateTrayIconService();
            try
            {
                owner.Show();
                _ = owner.Activate();
                owner.UpdateLayout();
                PumpDispatcherFor(TimeSpan.FromMilliseconds(100));
                var anchor = owner.PointToScreen(new Point(50, 50));
                var outside = owner.PointToScreen(new Point(680, 440));
                var click = Task.Run(async () =>
                {
                    await Task.Delay(350);
                    var moved = SendMouseMove((int)outside.X, (int)outside.Y);
                    NativeInput[] input =
                    [
                        NativeInput.Mouse(MouseEventLeftDown),
                        NativeInput.Mouse(MouseEventLeftUp),
                    ];
                    var sent = SendInputNative(
                        (uint)input.Length,
                        input,
                        Marshal.SizeOf<NativeInput>()) == input.Length;
                    await Task.Delay(1_650);
                    _ = EndMenu();
                    return moved && sent;
                });

                var stopwatch = Stopwatch.StartNew();
                var command = TrayContextMenuFactory.Show(
                    trayService.OwnerWindowHandle,
                    new PixelPoint((int)anchor.X, (int)anchor.Y));
                stopwatch.Stop();
                var cursorMoved = click.GetAwaiter().GetResult();

                Assert.Equal(TrayContextMenuCommand.None, command);
                Assert.True(cursorMoved);
                Assert.InRange(
                    stopwatch.Elapsed,
                    TimeSpan.FromMilliseconds(200),
                    TimeSpan.FromMilliseconds(1_200));
            }
            finally
            {
                _ = SetCursorPos(originalCursor.X, originalCursor.Y);
                owner.Close();
            }
        });
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Hardware)]
    public void NativeTrayIconRealSendInputPrimaryInvokesOnce()
    {
        StaTestHost.Run(() =>
        {
            if (!InteractiveTrayTestWasRequested())
            {
                return;
            }

            if (!Environment.UserInteractive || !GetCursorPos(out var originalCursor))
            {
                throw new InvalidOperationException(
                    "The interactive tray test requires access to the user's input desktop.");
            }

            var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "Battuta.ico");
            var iconHandle = NativeTrayIconService.LoadIconFromFile(iconPath, 16);
            using var service = new NativeTrayIconService(
                iconHandle,
                tooltip: "Battuta tray SendInput test",
                iconGuid: Guid.NewGuid(),
                ownsIconHandle: true);
            var primaryInvocations = 0;
            service.Invoked += (_, eventArgs) =>
                primaryInvocations += eventArgs.Invocation == TrayIconInvocation.Primary ? 1 : 0;
            try
            {
                service.Show();
                PixelRect bounds;
                try
                {
                    bounds = WaitForTrayBounds(service);
                }
                catch (InvalidOperationException exception)
                {
                    Assert.Skip(exception.Message);
                    return;
                }

                Assert.True(bounds.Width > 0 && bounds.Height > 0);
                if (!SendMouseMove(bounds.CenterX, bounds.CenterY))
                {
                    Assert.Skip("SendInput could not move the cursor on this input desktop.");
                    return;
                }

                PumpDispatcherFor(TimeSpan.FromMilliseconds(100));
                Assert.True(GetCursorPos(out var movedCursor));
                if (Math.Abs(movedCursor.X - bounds.CenterX) > 2
                    || Math.Abs(movedCursor.Y - bounds.CenterY) > 2)
                {
                    Assert.Skip(
                        $"The temporary GUID icon is not reachable on this input desktop: "
                        + $"Shell reported [{bounds.CenterX},{bounds.CenterY}], "
                        + $"SendInput reached [{movedCursor.X},{movedCursor.Y}].");
                    return;
                }

                NativeInput[] input =
                [
                    NativeInput.Mouse(MouseEventLeftDown),
                    NativeInput.Mouse(MouseEventLeftUp),
                ];
                Assert.Equal(
                    (uint)input.Length,
                    SendInputNative((uint)input.Length, input, Marshal.SizeOf<NativeInput>()));
                PumpDispatcherFor(TimeSpan.FromMilliseconds(750));

                Assert.True(
                    primaryInvocations == 1,
                    $"Expected one primary invocation after SendInput at "
                    + $"[{bounds.Left},{bounds.Top},{bounds.Right},{bounds.Bottom}], "
                    + $"cursor ended at [{movedCursor.X},{movedCursor.Y}], observed {primaryInvocations}.");
            }
            finally
            {
                _ = SendMouseMove(originalCursor.X, originalCursor.Y);
                if (service.IsVisible)
                {
                    service.Hide();
                }
            }
        });
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void NativeContextMenuUsesCaptureDismissalAndPostsTheRequiredFollowUpMessage()
    {
        var source = File.ReadAllText(FindProductSource(
            "Views",
            "Tray",
            "TrayContextMenuFactory.cs"));

        Assert.Equal(0u, (uint)TrayContextMenuCommand.None);
        Assert.Contains(
            "TpmRightButton | TpmNonotify | TpmReturnCommand | TpmWorkArea",
            source,
            StringComparison.Ordinal);
        Assert.Contains(
            "PostMessage(ownerWindow, WmNull, IntPtr.Zero, IntPtr.Zero)",
            source,
            StringComparison.Ordinal);
        Assert.Contains("DestroyMenu(menu)", source, StringComparison.Ordinal);
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void NativeContextMenuDisablesTheUnusedCheckAndIconGutter()
    {
        var menu = CreatePopupMenu();
        Assert.NotEqual(IntPtr.Zero, menu);
        try
        {
            var configure = typeof(TrayContextMenuFactory).GetMethod(
                "ConfigureMenuStyle",
                BindingFlags.Static | BindingFlags.NonPublic)
                ?? throw new MissingMethodException(
                    typeof(TrayContextMenuFactory).FullName,
                    "ConfigureMenuStyle");
            _ = configure.Invoke(null, [menu]);

            var information = new MenuInfo
            {
                Size = (uint)Marshal.SizeOf<MenuInfo>(),
                Mask = MimStyle,
            };
            Assert.True(GetMenuInfo(menu, ref information));
            Assert.Equal(MnsNoCheck, information.Style & MnsNoCheck);
        }
        finally
        {
            Assert.True(DestroyMenu(menu));
        }
    }

    private static NativeTrayIconService CreateTrayIconService(TimeProvider? timeProvider = null)
    {
        var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "Battuta.ico");
        var iconHandle = NativeTrayIconService.LoadIconFromFile(iconPath, 16);
        return new NativeTrayIconService(
            iconHandle,
            ownsIconHandle: true,
            timeProvider: timeProvider);
    }

    private static bool DispatchNotification(
        NativeTrayIconService service,
        int notification,
        IntPtr screenPoint)
    {
        var procedure = typeof(NativeTrayIconService).GetMethod(
            "WindowProcedure",
            BindingFlags.Instance | BindingFlags.NonPublic)
            ?? throw new MissingMethodException(typeof(NativeTrayIconService).FullName, "WindowProcedure");
        object?[] arguments =
        [
            IntPtr.Zero,
            CallbackMessage,
            screenPoint,
            new IntPtr(notification),
            false,
        ];

        _ = procedure.Invoke(service, arguments);
        return Assert.IsType<bool>(arguments[4]);
    }

    private static IntPtr PackPoint(short x, short y) => new(
        unchecked((int)((uint)(ushort)x | ((uint)(ushort)y << 16))));

    private static string FindProductSource(params string[] relativeSegments)
    {
        for (var current = new DirectoryInfo(AppContext.BaseDirectory);
             current is not null;
             current = current.Parent)
        {
            if (File.Exists(Path.Combine(current.FullName, "WINDOWS_PORTING_HANDOFF.md")))
            {
                return Path.Combine(
                    [
                        current.FullName,
                        "BattutaWindows",
                        "src",
                        "Battuta.Windows",
                        .. relativeSegments,
                    ]);
            }
        }

        throw new DirectoryNotFoundException(
            $"Could not locate the Battuta repository above '{AppContext.BaseDirectory}'.");
    }

    private static DateTime ReadSuppressionDeadline(TrayFlyoutWindow window)
    {
        var field = typeof(TrayFlyoutWindow).GetField(
            "_ignoreDeactivationUntilUtc",
            BindingFlags.Instance | BindingFlags.NonPublic)
            ?? throw new MissingFieldException(
                typeof(TrayFlyoutWindow).FullName,
                "_ignoreDeactivationUntilUtc");
        return Assert.IsType<DateTime>(field.GetValue(window));
    }

    private static bool InteractiveTrayTestWasRequested() => string.Equals(
        Environment.GetEnvironmentVariable("BATTUTA_REQUIRE_INTERACTIVE_TRAY_TEST"),
        "1",
        StringComparison.Ordinal);

    private static PixelRect WaitForTrayBounds(NativeTrayIconService service)
    {
        for (var attempt = 0; attempt < 12; attempt++)
        {
            PumpDispatcherFor(TimeSpan.FromMilliseconds(100));
            if (service.TryGetBounds(out var bounds) && bounds.Width > 0 && bounds.Height > 0)
            {
                return bounds;
            }
        }

        throw new InvalidOperationException(
            "Explorer did not expose bounds for the temporary tray icon within 1.2 seconds.");
    }

    private static bool SendMouseMove(int x, int y)
    {
        const int virtualLeftIndex = 76;
        const int virtualTopIndex = 77;
        const int virtualWidthIndex = 78;
        const int virtualHeightIndex = 79;
        var previousDpiContext = SetThreadDpiAwarenessContext(new IntPtr(-4));
        int left;
        int top;
        int width;
        int height;
        try
        {
            left = GetSystemMetrics(virtualLeftIndex);
            top = GetSystemMetrics(virtualTopIndex);
            width = GetSystemMetrics(virtualWidthIndex);
            height = GetSystemMetrics(virtualHeightIndex);
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
            NativeInput.MouseMove(normalizedX, normalizedY),
        ];
        return SendInputNative(1, input, Marshal.SizeOf<NativeInput>()) == 1;
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

    private sealed class ManualTimeProvider : TimeProvider
    {
        private long timestamp;

        public override long TimestampFrequency => TimeSpan.TicksPerSecond;

        public override long GetTimestamp() => timestamp;

        public override DateTimeOffset GetUtcNow() =>
            DateTimeOffset.UnixEpoch.AddTicks(timestamp);

        public void Advance(TimeSpan elapsed)
        {
            ArgumentOutOfRangeException.ThrowIfLessThan(elapsed, TimeSpan.Zero);
            timestamp = checked(timestamp + elapsed.Ticks);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeInput
    {
        public uint Type;
        public NativeInputUnion Value;

        public static NativeInput Mouse(uint flags) => new()
        {
            Type = 0,
            Value = new NativeInputUnion
            {
                Mouse = new NativeMouseInput { Flags = flags },
            },
        };

        public static NativeInput MouseMove(int x, int y) => new()
        {
            Type = 0,
            Value = new NativeInputUnion
            {
                Mouse = new NativeMouseInput
                {
                    X = x,
                    Y = y,
                    Flags = MouseEventMove | MouseEventAbsolute | MouseEventVirtualDesk,
                },
            },
        };
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct NativeInputUnion
    {
        [FieldOffset(0)]
        public NativeMouseInput Mouse;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeMouseInput
    {
        public int X;
        public int Y;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public UIntPtr ExtraInformation;
    }

    private const uint MimStyle = 0x00000010;
    private const uint MnsNoCheck = 0x80000000;
    private const uint MouseEventLeftDown = 0x0002;
    private const uint MouseEventLeftUp = 0x0004;
    private const uint MouseEventMove = 0x0001;
    private const uint MouseEventVirtualDesk = 0x4000;
    private const uint MouseEventAbsolute = 0x8000;

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MenuInfo
    {
        public uint Size;
        public uint Mask;
        public uint Style;
        public uint MaximumHeight;
        public IntPtr BackgroundBrush;
        public uint ContextHelpId;
        public UIntPtr MenuData;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr CreatePopupMenu();

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMenuInfo(IntPtr menu, ref MenuInfo information);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyMenu(IntPtr menu);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out NativePoint point);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll", EntryPoint = "SendInput", SetLastError = true)]
    private static extern uint SendInputNative(
        uint inputCount,
        [In] NativeInput[] inputs,
        int inputSize);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll")]
    private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EndMenu();
}
