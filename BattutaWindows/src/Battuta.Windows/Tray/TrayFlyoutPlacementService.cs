using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace Battuta.Windows.Tray;

/// <summary>
/// Converts WPF DIP dimensions to the target monitor's physical pixels and
/// moves the flyout without relying on a hard-coded bottom-right taskbar.
/// </summary>
public sealed class TrayFlyoutPlacementService(ITrayIconService trayIcon)
{
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpNoZOrder = 0x0004;
    private const uint MonitorDefaultToNearest = 0x00000002;
    private readonly ITrayIconService _trayIcon = trayIcon ?? throw new ArgumentNullException(nameof(trayIcon));

    public bool TryPlace(
        Window window,
        PixelPoint? fallbackAnchor = null,
        int gapInPhysicalPixels = 8)
    {
        ArgumentNullException.ThrowIfNull(window);
        window.Dispatcher.VerifyAccess();
        if (!_trayIcon.TryGetBounds(out var iconBounds))
        {
            if (fallbackAnchor is not { } anchor)
            {
                return false;
            }

            iconBounds = new PixelRect(anchor.X, anchor.Y, anchor.X + 1, anchor.Y + 1);
        }

        var nativeIconRect = new NativeRect
        {
            Left = iconBounds.Left,
            Top = iconBounds.Top,
            Right = iconBounds.Right,
            Bottom = iconBounds.Bottom,
        };
        var monitor = MonitorFromRect(ref nativeIconRect, MonitorDefaultToNearest);
        if (monitor == IntPtr.Zero)
        {
            return false;
        }

        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (!GetMonitorInfo(monitor, ref info))
        {
            return false;
        }

        var helper = new WindowInteropHelper(window);
        var hwnd = helper.EnsureHandle();
        var dpi = GetMonitorDpi(monitor);
        if (dpi == 0)
        {
            dpi = GetDpiForWindow(hwnd);
        }
        if (dpi == 0)
        {
            dpi = 96;
        }

        var widthDip = ResolveDimension(window.ActualWidth, window.Width, 360);
        var heightDip = ResolveDimension(window.ActualHeight, window.Height, 760);
        var requested = new PixelSize(
            Math.Max(1, (int)Math.Ceiling(widthDip * dpi / 96d)),
            Math.Max(1, (int)Math.Ceiling(heightDip * dpi / 96d)));
        var workArea = new PixelRect(
            info.Work.Left,
            info.Work.Top,
            info.Work.Right,
            info.Work.Bottom);
        var placement = TrayFlyoutPositioner.Calculate(
            iconBounds,
            workArea,
            requested,
            gapInPhysicalPixels);

        return SetWindowPos(
            hwnd,
            IntPtr.Zero,
            placement.X,
            placement.Y,
            placement.Width,
            placement.Height,
            SwpNoActivate | SwpNoZOrder);
    }

    private static double ResolveDimension(double actual, double declared, double fallback)
    {
        if (double.IsFinite(actual) && actual > 0)
        {
            return actual;
        }

        return double.IsFinite(declared) && declared > 0 ? declared : fallback;
    }

    private static uint GetMonitorDpi(IntPtr monitor)
    {
        try
        {
            return GetDpiForMonitor(monitor, 0, out var x, out _) == 0 ? x : 0;
        }
        catch (DllNotFoundException)
        {
            return 0;
        }
        catch (EntryPointNotFoundException)
        {
            return 0;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MonitorInfo
    {
        public int Size;
        public NativeRect Monitor;
        public NativeRect Work;
        public uint Flags;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromRect(ref NativeRect rect, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hwnd);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(
        IntPtr monitor,
        int dpiType,
        out uint dpiX,
        out uint dpiY);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(
        IntPtr hwnd,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);
}
