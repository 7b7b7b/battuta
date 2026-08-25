using System.Runtime.InteropServices;
using System.Windows;

namespace Battuta.Windows.Tray;

public static class TrayScreenCoordinateConverter
{
    private const uint MonitorDefaultToNearest = 0x00000002;

    /// <summary>
    /// Converts notification-area physical coordinates into the DIPs expected
    /// by WPF AbsolutePoint placement on the target monitor.
    /// </summary>
    public static Point PhysicalPixelsToDips(PixelPoint point)
    {
        var nativePoint = new NativePoint { X = point.X, Y = point.Y };
        var monitor = MonitorFromPoint(nativePoint, MonitorDefaultToNearest);
        var dpi = GetEffectiveDpi(monitor);
        return new Point(point.X * 96d / dpi, point.Y * 96d / dpi);
    }

    private static uint GetEffectiveDpi(IntPtr monitor)
    {
        if (monitor == IntPtr.Zero)
        {
            return GetSystemDpi();
        }

        try
        {
            if (GetDpiForMonitor(monitor, 0, out var dpiX, out _) == 0 && dpiX > 0)
            {
                return dpiX;
            }
        }
        catch (DllNotFoundException)
        {
        }
        catch (EntryPointNotFoundException)
        {
        }

        return GetSystemDpi();
    }

    private static uint GetSystemDpi()
    {
        try
        {
            var dpi = GetDpiForSystem();
            return dpi == 0 ? 96u : dpi;
        }
        catch (EntryPointNotFoundException)
        {
            return 96;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromPoint(NativePoint point, uint flags);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForSystem();

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(
        IntPtr monitor,
        int dpiType,
        out uint dpiX,
        out uint dpiY);
}
