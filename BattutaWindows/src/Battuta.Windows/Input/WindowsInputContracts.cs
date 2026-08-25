using Battuta.Core.Input;

namespace Battuta.Windows.Input;

public enum WindowsScanCodePrefix
{
    Base,
    E0,
    E1,
}

public enum WindowsInputOrigin
{
    Hardware,
    Injected,
    LowerIntegrityInjected,
}

public enum WindowsPointerButton
{
    Primary,
    Secondary,
    Middle,
    X1,
    X2,
}

public enum WindowsRawInputKind
{
    Reset,
    Keyboard,
    Mouse,
}

public readonly record struct WindowsPhysicalKey(
    PhysicalKeyId Id,
    KeyboardRowId Row,
    KeyboardSpecialKeyId? SpecialKey,
    bool IsDiyAssignable,
    bool IsKnown);

public readonly record struct RawWindowsKeyboardEvent(
    WindowsPhysicalKey Key,
    WindowsScanCodePrefix ScanCodePrefix,
    ushort ScanCode,
    KeyPhase Phase,
    bool IsRepeat,
    WindowsInputOrigin Origin,
    uint NativeTimestamp,
    long MonotonicTimestamp,
    ulong Sequence);

public readonly record struct RawWindowsPointerEvent(
    WindowsPointerButton Button,
    KeyPhase Phase,
    WindowsInputOrigin Origin,
    uint NativeTimestamp,
    long MonotonicTimestamp,
    ulong Sequence);

public readonly record struct RawWindowsInputEvent
{
    private RawWindowsInputEvent(
        WindowsRawInputKind kind,
        RawWindowsKeyboardEvent keyboard,
        RawWindowsPointerEvent pointer,
        ulong sequence)
    {
        Kind = kind;
        Keyboard = keyboard;
        Mouse = pointer;
        Sequence = sequence;
    }

    public WindowsRawInputKind Kind { get; }

    public RawWindowsKeyboardEvent Keyboard { get; }

    public RawWindowsPointerEvent Mouse { get; }

    public ulong Sequence { get; }

    public static RawWindowsInputEvent FromKeyboard(RawWindowsKeyboardEvent value) =>
        new(WindowsRawInputKind.Keyboard, value, default, value.Sequence);

    public static RawWindowsInputEvent FromMouse(RawWindowsPointerEvent value) =>
        new(WindowsRawInputKind.Mouse, default, value, value.Sequence);

    public static RawWindowsInputEvent Reset(ulong sequence) =>
        new(WindowsRawInputKind.Reset, default, default, sequence);
}

public readonly record struct WindowsKeyboardInputEvent(
    WindowsPhysicalKey Key,
    KeyPhase Phase,
    bool IsRepeat,
    ModifierState Modifiers,
    bool IsShortcutModified,
    WindowsInputOrigin Origin,
    DateTimeOffset Timestamp,
    ulong Sequence);

public readonly record struct WindowsPointerInputEvent(
    WindowsPointerButton Button,
    KeyPhase Phase,
    WindowsInputOrigin Origin,
    DateTimeOffset Timestamp,
    ulong Sequence);

public enum WindowsInputKind
{
    Keyboard,
    Mouse,
}

public readonly record struct WindowsInputEvent
{
    private WindowsInputEvent(
        WindowsInputKind kind,
        WindowsKeyboardInputEvent keyboard,
        WindowsPointerInputEvent pointer,
        ForegroundApplicationSnapshot foregroundApplication)
    {
        Kind = kind;
        Keyboard = keyboard;
        Mouse = pointer;
        ForegroundApplication = foregroundApplication;
    }

    public WindowsInputKind Kind { get; }

    public WindowsKeyboardInputEvent Keyboard { get; }

    public WindowsPointerInputEvent Mouse { get; }

    public ForegroundApplicationSnapshot ForegroundApplication { get; }

    public static WindowsInputEvent FromKeyboard(
        WindowsKeyboardInputEvent value,
        ForegroundApplicationSnapshot foregroundApplication) =>
        new(WindowsInputKind.Keyboard, value, default, foregroundApplication);

    public static WindowsInputEvent FromMouse(
        WindowsPointerInputEvent value,
        ForegroundApplicationSnapshot foregroundApplication) =>
        new(WindowsInputKind.Mouse, default, value, foregroundApplication);
}

public interface IWindowsInputEventSink
{
    ValueTask OnInputAsync(WindowsInputEvent inputEvent, CancellationToken cancellationToken);
}

public sealed class DelegateWindowsInputEventSink(
    Func<WindowsInputEvent, CancellationToken, ValueTask> handler) : IWindowsInputEventSink
{
    private readonly Func<WindowsInputEvent, CancellationToken, ValueTask> _handler =
        handler ?? throw new ArgumentNullException(nameof(handler));

    public ValueTask OnInputAsync(
        WindowsInputEvent inputEvent,
        CancellationToken cancellationToken) =>
        _handler(inputEvent, cancellationToken);
}
