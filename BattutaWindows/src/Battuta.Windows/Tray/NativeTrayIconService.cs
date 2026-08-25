using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace Battuta.Windows.Tray;

/// <summary>
/// Shell notification icon with a stable GUID, keyboard activation, exact icon
/// bounds, and Explorer-restart recovery.
/// </summary>
public sealed class NativeTrayIconService : ITrayIconService
{
    public static readonly Guid DefaultIconGuid = new("74C77CE9-C111-4EDD-A74D-4B7DF75F7019");
    public static TimeSpan InvocationDeduplicationWindow { get; } = TimeSpan.FromMilliseconds(300);

    private const uint CallbackMessage = 0x8001; // WM_APP + 1
    private const uint NimAdd = 0x00000000;
    private const uint NimModify = 0x00000001;
    private const uint NimDelete = 0x00000002;
    private const uint NimSetVersion = 0x00000004;
    private const uint NifMessage = 0x00000001;
    private const uint NifIcon = 0x00000002;
    private const uint NifTip = 0x00000004;
    private const uint NifGuid = 0x00000020;
    private const uint NotifyIconVersion4 = 4;
    private const int WmContextMenu = 0x007B;
    private const int WmLButtonUp = 0x0202;
    private const int WmRButtonUp = 0x0205;
    private const int NinSelect = 0x0400;
    private const int NinKeySelect = 0x0401;

    private readonly HwndSource _messageWindow;
    private readonly Guid _iconGuid;
    private readonly bool _ownsIconHandle;
    private readonly uint _taskbarCreatedMessage;
    private readonly TimeProvider _timeProvider;
    private IntPtr _iconHandle;
    private string _tooltip;
    private long _lastPrimaryInvocationTimestamp;
    private long _lastKeyboardInvocationTimestamp;
    private long _lastContextInvocationTimestamp;
    private int _seenInvocationMask;
    private int _activeInvocationMask;
    private bool _disposed;

    public NativeTrayIconService(
        IntPtr iconHandle,
        string tooltip = "Battuta",
        Guid? iconGuid = null,
        bool ownsIconHandle = false,
        TimeProvider? timeProvider = null)
    {
        if (iconHandle == IntPtr.Zero)
        {
            throw new ArgumentException("A valid native icon handle is required.", nameof(iconHandle));
        }

        _iconHandle = iconHandle;
        _tooltip = NormalizeTooltip(tooltip);
        _iconGuid = iconGuid ?? DefaultIconGuid;
        _ownsIconHandle = ownsIconHandle;
        _timeProvider = timeProvider ?? TimeProvider.System;
        _taskbarCreatedMessage = RegisterWindowMessage("TaskbarCreated");

        var parameters = new HwndSourceParameters("Battuta.TrayMessageWindow")
        {
            WindowStyle = unchecked((int)0x80000000), // WS_POPUP
            ExtendedWindowStyle = 0x00000080, // WS_EX_TOOLWINDOW
            Width = 0,
            Height = 0,
        };
        _messageWindow = new HwndSource(parameters);
        _messageWindow.AddHook(WindowProcedure);
    }

    public event EventHandler<TrayIconInvokedEventArgs>? Invoked;

    public bool IsVisible { get; private set; }

    public IntPtr OwnerWindowHandle
    {
        get
        {
            VerifyAccessAndState();
            return _messageWindow.Handle;
        }
    }

    public void Show()
    {
        VerifyAccessAndState();
        if (IsVisible)
        {
            return;
        }

        AddToShell();
        IsVisible = true;
    }

    public void Hide()
    {
        VerifyAccessAndState();
        if (!IsVisible)
        {
            return;
        }

        var data = CreateData(NifGuid);
        _ = Shell_NotifyIcon(NimDelete, ref data);
        IsVisible = false;
    }

    public void SetTooltip(string tooltip)
    {
        VerifyAccessAndState();
        _tooltip = NormalizeTooltip(tooltip);
        if (!IsVisible)
        {
            return;
        }

        var data = CreateData(NifGuid | NifTip);
        if (!Shell_NotifyIcon(NimModify, ref data))
        {
            _ = RecoverAfterExplorerRestartAsync();
        }
    }

    public bool TryGetBounds(out PixelRect bounds)
    {
        VerifyAccessAndState();
        var identifier = new NotifyIconIdentifier
        {
            CbSize = Marshal.SizeOf<NotifyIconIdentifier>(),
            HWnd = _messageWindow.Handle,
            Id = 1,
            GuidItem = _iconGuid,
        };
        var result = Shell_NotifyIconGetRect(ref identifier, out var rect);
        bounds = result >= 0
            ? new PixelRect(rect.Left, rect.Top, rect.Right, rect.Bottom)
            : default;
        return result >= 0;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        if (_messageWindow.Dispatcher.CheckAccess())
        {
            DisposeOnDispatcher();
        }
        else
        {
            _messageWindow.Dispatcher.Invoke(DisposeOnDispatcher);
        }

        GC.SuppressFinalize(this);
    }

    public static IntPtr LoadIconFromFile(string iconPath, int pixelSize = 32)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(iconPath);
        var handle = LoadImage(
            IntPtr.Zero,
            Path.GetFullPath(iconPath),
            imageType: 1,
            pixelSize,
            pixelSize,
            0x0010); // LR_LOADFROMFILE
        if (handle == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), $"Unable to load tray icon: {iconPath}");
        }

        return handle;
    }

    private void AddToShell()
    {
        var data = CreateData(NifGuid | NifMessage | NifIcon | NifTip);
        if (!Shell_NotifyIcon(NimAdd, ref data))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to add the Battuta tray icon.");
        }

        data.TimeoutOrVersion = NotifyIconVersion4;
        if (!Shell_NotifyIcon(NimSetVersion, ref data))
        {
            var cleanup = CreateData(NifGuid);
            _ = Shell_NotifyIcon(NimDelete, ref cleanup);
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to set the Battuta tray icon protocol version.");
        }
    }

    private IntPtr WindowProcedure(
        IntPtr hwnd,
        int message,
        IntPtr wParam,
        IntPtr lParam,
        ref bool handled)
    {
        if ((uint)message == _taskbarCreatedMessage && IsVisible)
        {
            _ = RecoverAfterExplorerRestartAsync();
            handled = true;
            return IntPtr.Zero;
        }

        if ((uint)message != CallbackMessage)
        {
            return IntPtr.Zero;
        }

        var notification = unchecked((int)(lParam.ToInt64() & 0xFFFF));
        var screenPoint = notification is NinSelect
            or NinKeySelect
            or WmContextMenu
            or WmLButtonUp
            or WmRButtonUp
            ? ReadScreenPoint(wParam)
            : null;
        switch (notification)
        {
            case NinSelect:
            case WmLButtonUp:
                _ = TryDispatchInvocation(TrayIconInvocation.Primary, screenPoint);
                handled = true;
                break;
            case NinKeySelect:
                _ = TryDispatchInvocation(
                    TrayIconInvocation.Keyboard,
                    ResolveKeyboardAnchor(screenPoint));
                handled = true;
                break;
            case WmContextMenu:
            case WmRButtonUp:
                _ = TryDispatchInvocation(
                    TrayIconInvocation.ContextMenu,
                    ResolveKeyboardAnchor(screenPoint));
                handled = true;
                break;
        }

        return IntPtr.Zero;
    }

    private bool TryDispatchInvocation(
        TrayIconInvocation invocation,
        PixelPoint? screenPoint)
    {
        var mask = 1 << (int)invocation;
        var now = _timeProvider.GetTimestamp();
        if ((_activeInvocationMask & mask) != 0
            || ((_seenInvocationMask & mask) != 0
                && _timeProvider.GetElapsedTime(LastTimestamp(invocation), now)
                    <= InvocationDeduplicationWindow))
        {
            return false;
        }

        SetLastTimestamp(invocation, now);
        _seenInvocationMask |= mask;
        _activeInvocationMask |= mask;
        try
        {
            Invoked?.Invoke(this, new TrayIconInvokedEventArgs(invocation, screenPoint));
            return true;
        }
        finally
        {
            // A context-menu handler can run a nested TrackPopupMenuEx message
            // loop for seconds. Refresh the deadline after it returns so a
            // queued partner notification cannot reopen the menu.
            SetLastTimestamp(invocation, _timeProvider.GetTimestamp());
            _activeInvocationMask &= ~mask;
        }
    }

    private long LastTimestamp(TrayIconInvocation invocation) => invocation switch
    {
        TrayIconInvocation.Primary => _lastPrimaryInvocationTimestamp,
        TrayIconInvocation.Keyboard => _lastKeyboardInvocationTimestamp,
        TrayIconInvocation.ContextMenu => _lastContextInvocationTimestamp,
        _ => 0,
    };

    private void SetLastTimestamp(TrayIconInvocation invocation, long timestamp)
    {
        switch (invocation)
        {
            case TrayIconInvocation.Primary:
                _lastPrimaryInvocationTimestamp = timestamp;
                break;
            case TrayIconInvocation.Keyboard:
                _lastKeyboardInvocationTimestamp = timestamp;
                break;
            case TrayIconInvocation.ContextMenu:
                _lastContextInvocationTimestamp = timestamp;
                break;
        }
    }

    private PixelPoint? ResolveKeyboardAnchor(PixelPoint? suppliedPoint)
    {
        if (suppliedPoint is not null)
        {
            return suppliedPoint;
        }

        return TryGetBounds(out var bounds)
            ? new PixelPoint(bounds.CenterX, bounds.CenterY)
            : null;
    }

    private static PixelPoint? ReadScreenPoint(IntPtr value)
    {
        var packed = unchecked((long)value);
        var x = unchecked((short)(packed & 0xFFFF));
        var y = unchecked((short)((packed >> 16) & 0xFFFF));
        return x == -1 && y == -1 ? null : new PixelPoint(x, y);
    }

    private async Task RecoverAfterExplorerRestartAsync()
    {
        for (var attempt = 0; attempt < 4; attempt++)
        {
            if (_disposed || !IsVisible)
            {
                return;
            }

            if (attempt > 0)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(250 * attempt));
            }

            if (_disposed || !IsVisible)
            {
                return;
            }

            try
            {
                AddToShell();
                return;
            }
            catch (Win32Exception)
            {
                // Explorer can broadcast TaskbarCreated before the notification
                // area accepts icons. Retry without throwing through WndProc.
            }
        }
    }

    private NotifyIconData CreateData(uint flags) => new()
    {
        CbSize = Marshal.SizeOf<NotifyIconData>(),
        HWnd = _messageWindow.Handle,
        Id = 1,
        Flags = flags,
        CallbackMessage = CallbackMessage,
        Icon = _iconHandle,
        Tip = _tooltip,
        Info = string.Empty,
        InfoTitle = string.Empty,
        GuidItem = _iconGuid,
    };

    private void VerifyAccessAndState()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        _messageWindow.Dispatcher.VerifyAccess();
    }

    private void DisposeOnDispatcher()
    {
        if (_disposed)
        {
            return;
        }

        if (IsVisible)
        {
            var data = CreateData(NifGuid);
            _ = Shell_NotifyIcon(NimDelete, ref data);
            IsVisible = false;
        }

        _messageWindow.RemoveHook(WindowProcedure);
        _messageWindow.Dispose();
        if (_ownsIconHandle && _iconHandle != IntPtr.Zero)
        {
            _ = DestroyIcon(_iconHandle);
            _iconHandle = IntPtr.Zero;
        }

        _disposed = true;
    }

    private static string NormalizeTooltip(string? tooltip)
    {
        var value = string.IsNullOrWhiteSpace(tooltip) ? "Battuta" : tooltip.Trim();
        return value.Length <= 127 ? value : value[..127];
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyIconData
    {
        public int CbSize;
        public IntPtr HWnd;
        public uint Id;
        public uint Flags;
        public uint CallbackMessage;
        public IntPtr Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string Tip;
        public uint State;
        public uint StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string Info;
        public uint TimeoutOrVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string InfoTitle;
        public uint InfoFlags;
        public Guid GuidItem;
        public IntPtr BalloonIcon;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NotifyIconIdentifier
    {
        public int CbSize;
        public IntPtr HWnd;
        public uint Id;
        public Guid GuidItem;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Shell_NotifyIcon(uint message, ref NotifyIconData data);

    [DllImport("shell32.dll")]
    private static extern int Shell_NotifyIconGetRect(
        ref NotifyIconIdentifier identifier,
        out NativeRect iconLocation);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint RegisterWindowMessage(string messageName);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadImage(
        IntPtr instance,
        string name,
        uint imageType,
        int width,
        int height,
        uint loadFlags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr icon);
}
