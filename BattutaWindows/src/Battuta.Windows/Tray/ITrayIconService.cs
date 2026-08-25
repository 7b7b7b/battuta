namespace Battuta.Windows.Tray;

public enum TrayIconInvocation
{
    Primary,
    Keyboard,
    ContextMenu,
}

public sealed class TrayIconInvokedEventArgs(
    TrayIconInvocation invocation,
    PixelPoint? screenPoint = null) : EventArgs
{
    public TrayIconInvocation Invocation { get; } = invocation;

    /// <summary>
    /// Physical screen coordinates supplied by NOTIFYICON_VERSION_4. Keyboard
    /// invocation falls back to the notification icon's center when possible.
    /// </summary>
    public PixelPoint? ScreenPoint { get; } = screenPoint;
}

public interface ITrayIconService : IDisposable
{
    event EventHandler<TrayIconInvokedEventArgs>? Invoked;

    bool IsVisible { get; }

    void Show();

    void Hide();

    void SetTooltip(string tooltip);

    bool TryGetBounds(out PixelRect bounds);
}
