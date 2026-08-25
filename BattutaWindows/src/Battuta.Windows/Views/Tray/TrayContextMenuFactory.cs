using System.ComponentModel;
using System.Runtime.InteropServices;
using Battuta.Windows.Tray;

namespace Battuta.Windows.Views.Tray;

public enum TrayContextMenuCommand : uint
{
    None = 0,
    OpenPanel = 1001,
    OpenStatistics = 1002,
    OpenDiyEditor = 1003,
    ExitApplication = 1004,
}

/// <summary>
/// Displays a real Win32 popup menu. TrackPopupMenuEx owns mouse capture and
/// its nested message loop, so an outside click reliably dismisses the menu.
/// MNS_NOCHECK removes the unused icon/check gutter that appeared as white
/// blocks in the WPF ContextMenu implementation.
/// </summary>
public static class TrayContextMenuFactory
{
    private const uint MfString = 0x00000000;
    private const uint MfSeparator = 0x00000800;
    private const uint MimStyle = 0x00000010;
    private const uint MnsNoCheck = 0x80000000;
    private const uint TpmRightButton = 0x0002;
    private const uint TpmNonotify = 0x0080;
    private const uint TpmReturnCommand = 0x0100;
    private const uint TpmWorkArea = 0x10000;
    private const uint WmNull = 0x0000;

    public static TrayContextMenuCommand Show(
        IntPtr ownerWindow,
        PixelPoint? anchor = null)
    {
        if (ownerWindow == IntPtr.Zero)
        {
            throw new ArgumentException("A native owner window is required.", nameof(ownerWindow));
        }

        var menu = CreatePopupMenu();
        if (menu == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "无法创建 Battuta 托盘菜单。");
        }

        try
        {
            ConfigureMenuStyle(menu);
            AppendCommand(menu, TrayContextMenuCommand.OpenPanel, "打开 Battuta");
            AppendCommand(menu, TrayContextMenuCommand.OpenStatistics, "输入统计");
            AppendCommand(menu, TrayContextMenuCommand.OpenDiyEditor, "DIY 音色编辑器");
            if (!AppendMenu(menu, MfSeparator, UIntPtr.Zero, null))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "无法创建托盘菜单分隔线。");
            }

            AppendCommand(menu, TrayContextMenuCommand.ExitApplication, "退出 Battuta");

            var point = ResolveAnchor(anchor);
            _ = SetForegroundWindow(ownerWindow);
            var command = TrackPopupMenuEx(
                menu,
                TpmRightButton | TpmNonotify | TpmReturnCommand | TpmWorkArea,
                point.X,
                point.Y,
                ownerWindow,
                IntPtr.Zero);

            // Required by the notification-area popup-menu contract: hand the
            // owner another message after TrackPopupMenuEx returns so the next
            // click does not leave the menu in a sticky foreground state.
            _ = PostMessage(ownerWindow, WmNull, IntPtr.Zero, IntPtr.Zero);
            return Enum.IsDefined(typeof(TrayContextMenuCommand), command)
                ? (TrayContextMenuCommand)command
                : TrayContextMenuCommand.None;
        }
        finally
        {
            _ = DestroyMenu(menu);
        }
    }

    private static void ConfigureMenuStyle(IntPtr menu)
    {
        var information = new MenuInfo
        {
            Size = (uint)Marshal.SizeOf<MenuInfo>(),
            Mask = MimStyle,
            Style = MnsNoCheck,
        };
        if (!SetMenuInfo(menu, ref information))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "无法配置 Battuta 托盘菜单。");
        }
    }

    private static void AppendCommand(
        IntPtr menu,
        TrayContextMenuCommand command,
        string title)
    {
        if (!AppendMenu(menu, MfString, new UIntPtr((uint)command), title))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), $"无法添加托盘菜单项：{title}");
        }
    }

    private static NativePoint ResolveAnchor(PixelPoint? anchor)
    {
        if (anchor is { } supplied)
        {
            return new NativePoint { X = supplied.X, Y = supplied.Y };
        }

        if (!GetCursorPos(out var cursor))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "无法读取托盘菜单位置。");
        }

        return cursor;
    }

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

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AppendMenu(
        IntPtr menu,
        uint flags,
        UIntPtr item,
        string? title);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetMenuInfo(IntPtr menu, ref MenuInfo information);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint TrackPopupMenuEx(
        IntPtr menu,
        uint flags,
        int x,
        int y,
        IntPtr ownerWindow,
        IntPtr parameters);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyMenu(IntPtr menu);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out NativePoint point);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostMessage(
        IntPtr window,
        uint message,
        IntPtr wParam,
        IntPtr lParam);
}
