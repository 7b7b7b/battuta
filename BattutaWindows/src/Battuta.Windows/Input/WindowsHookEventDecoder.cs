using Battuta.Core.Input;

namespace Battuta.Windows.Input;

/// <summary>Pure decoding logic shared by the unmanaged callbacks and unit tests.</summary>
public static class WindowsHookEventDecoder
{
    public const uint KeyDownMessage = 0x0100;
    public const uint KeyUpMessage = 0x0101;
    public const uint SystemKeyDownMessage = 0x0104;
    public const uint SystemKeyUpMessage = 0x0105;
    public const uint LeftButtonDownMessage = 0x0201;
    public const uint LeftButtonUpMessage = 0x0202;
    public const uint RightButtonDownMessage = 0x0204;
    public const uint RightButtonUpMessage = 0x0205;
    public const uint MiddleButtonDownMessage = 0x0207;
    public const uint MiddleButtonUpMessage = 0x0208;
    public const uint XButtonDownMessage = 0x020B;
    public const uint XButtonUpMessage = 0x020C;

    public const uint KeyboardFlagExtended = 0x01;
    public const uint KeyboardFlagLowerIntegrityInjected = 0x02;
    public const uint KeyboardFlagInjected = 0x10;
    public const uint MouseFlagInjected = 0x01;
    public const uint MouseFlagLowerIntegrityInjected = 0x02;

    public static bool IsPointerButtonMessage(uint message) => message is
        LeftButtonDownMessage
        or LeftButtonUpMessage
        or RightButtonDownMessage
        or RightButtonUpMessage
        or MiddleButtonDownMessage
        or MiddleButtonUpMessage
        or XButtonDownMessage
        or XButtonUpMessage;

    public static bool TryDecodeKeyboard(
        uint message,
        uint virtualKey,
        uint scanCode,
        uint flags,
        nuint extraInfo,
        uint nativeTimestamp,
        long monotonicTimestamp,
        ulong sequence,
        nuint selfInjectionSentinel,
        WindowsKeyboardRepeatTracker repeatTracker,
        out RawWindowsKeyboardEvent input)
    {
        ArgumentNullException.ThrowIfNull(repeatTracker);

        if (extraInfo == selfInjectionSentinel
            || !TryGetKeyboardPhase(message, out var phase)
            || !WindowsScanCodeMapper.TryMapHookEvent(
                scanCode,
                (flags & KeyboardFlagExtended) != 0,
                virtualKey,
                out var prefix,
                out var key))
        {
            input = default;
            return false;
        }

        input = new RawWindowsKeyboardEvent(
            key,
            prefix,
            checked((ushort)scanCode),
            phase,
            repeatTracker.Observe(key.Id, phase),
            KeyboardOrigin(flags),
            nativeTimestamp,
            monotonicTimestamp,
            sequence);
        return true;
    }

    public static bool TryDecodePointer(
        uint message,
        uint mouseData,
        uint flags,
        nuint extraInfo,
        uint nativeTimestamp,
        long monotonicTimestamp,
        ulong sequence,
        nuint selfInjectionSentinel,
        out RawWindowsPointerEvent input)
    {
        if (extraInfo == selfInjectionSentinel
            || !TryGetPointerTransition(message, mouseData, out var button, out var phase))
        {
            input = default;
            return false;
        }

        input = new RawWindowsPointerEvent(
            button,
            phase,
            MouseOrigin(flags),
            nativeTimestamp,
            monotonicTimestamp,
            sequence);
        return true;
    }

    private static bool TryGetKeyboardPhase(uint message, out KeyPhase phase)
    {
        switch (message)
        {
            case KeyDownMessage:
            case SystemKeyDownMessage:
                phase = KeyPhase.Press;
                return true;
            case KeyUpMessage:
            case SystemKeyUpMessage:
                phase = KeyPhase.Release;
                return true;
            default:
                phase = default;
                return false;
        }
    }

    private static bool TryGetPointerTransition(
        uint message,
        uint mouseData,
        out WindowsPointerButton button,
        out KeyPhase phase)
    {
        switch (message)
        {
            case LeftButtonDownMessage:
                button = WindowsPointerButton.Primary;
                phase = KeyPhase.Press;
                return true;
            case LeftButtonUpMessage:
                button = WindowsPointerButton.Primary;
                phase = KeyPhase.Release;
                return true;
            case RightButtonDownMessage:
                button = WindowsPointerButton.Secondary;
                phase = KeyPhase.Press;
                return true;
            case RightButtonUpMessage:
                button = WindowsPointerButton.Secondary;
                phase = KeyPhase.Release;
                return true;
            case MiddleButtonDownMessage:
                button = WindowsPointerButton.Middle;
                phase = KeyPhase.Press;
                return true;
            case MiddleButtonUpMessage:
                button = WindowsPointerButton.Middle;
                phase = KeyPhase.Release;
                return true;
            case XButtonDownMessage:
            case XButtonUpMessage:
                var xButton = (mouseData >> 16) & 0xFFFF;
                if (xButton is not (1 or 2))
                {
                    button = default;
                    phase = default;
                    return false;
                }

                button = xButton == 1
                    ? WindowsPointerButton.X1
                    : WindowsPointerButton.X2;
                phase = message == XButtonDownMessage ? KeyPhase.Press : KeyPhase.Release;
                return true;
            default:
                button = default;
                phase = default;
                return false;
        }
    }

    private static WindowsInputOrigin KeyboardOrigin(uint flags) =>
        (flags & KeyboardFlagLowerIntegrityInjected) != 0
            ? WindowsInputOrigin.LowerIntegrityInjected
            : (flags & KeyboardFlagInjected) != 0
                ? WindowsInputOrigin.Injected
                : WindowsInputOrigin.Hardware;

    private static WindowsInputOrigin MouseOrigin(uint flags) =>
        (flags & MouseFlagLowerIntegrityInjected) != 0
            ? WindowsInputOrigin.LowerIntegrityInjected
            : (flags & MouseFlagInjected) != 0
                ? WindowsInputOrigin.Injected
                : WindowsInputOrigin.Hardware;
}
