using Battuta.Core.Input;

namespace Battuta.Windows.Input;

public sealed class WindowsKeyboardRepeatTracker
{
    private readonly HashSet<PhysicalKeyId> _pressedKeys = new(capacity: 256);

    public bool Observe(PhysicalKeyId key, KeyPhase phase)
    {
        if (phase == KeyPhase.Release)
        {
            _pressedKeys.Remove(key);
            return false;
        }

        return !_pressedKeys.Add(key);
    }

    public void Reset() => _pressedKeys.Clear();
}

public readonly record struct KeyboardNormalizationResult(
    int Count,
    WindowsKeyboardInputEvent First,
    WindowsKeyboardInputEvent Second)
{
    public static KeyboardNormalizationResult None => default;

    public static KeyboardNormalizationResult One(WindowsKeyboardInputEvent value) =>
        new(1, value, default);

    public static KeyboardNormalizationResult Two(
        WindowsKeyboardInputEvent first,
        WindowsKeyboardInputEvent second) =>
        new(2, first, second);
}

/// <summary>
/// Converts raw hook transitions into stable modifier semantics. In particular, it removes
/// the synthetic LeftControl transition emitted by Windows as part of an AltGr press.
/// </summary>
public sealed class WindowsKeyboardEventNormalizer
{
    public static readonly TimeSpan LeftControlLookahead = TimeSpan.FromMilliseconds(8);

    private RawWindowsKeyboardEvent? _pendingLeftControl;
    private ModifierState _modifiers;
    private bool _altGrActive;
    private bool _suppressSyntheticLeftControlRelease;

    public bool HasPendingEvent => _pendingLeftControl.HasValue;

    public long PendingDeadlineTimestamp => _pendingLeftControl is { } pending
        ? pending.MonotonicTimestamp + ToStopwatchTicks(LeftControlLookahead)
        : 0;

    public ModifierState Modifiers => _modifiers;

    public KeyboardNormalizationResult Process(
        RawWindowsKeyboardEvent input,
        DateTimeOffset timestamp)
    {
        if (IsSyntheticAltGrLeftControlRelease(input))
        {
            _suppressSyntheticLeftControlRelease = false;
            return KeyboardNormalizationResult.None;
        }

        if (_pendingLeftControl is { } pending)
        {
            _pendingLeftControl = null;
            if (IsAltGrPair(pending, input))
            {
                _altGrActive = true;
                _suppressSyntheticLeftControlRelease = true;
                return KeyboardNormalizationResult.One(Normalize(input, timestamp));
            }

            var first = Normalize(pending, timestamp);
            var second = Normalize(input, timestamp);
            return KeyboardNormalizationResult.Two(first, second);
        }

        if (IsLeftControlPressCandidate(input))
        {
            _pendingLeftControl = input;
            return KeyboardNormalizationResult.None;
        }

        return KeyboardNormalizationResult.One(Normalize(input, timestamp));
    }

    public WindowsKeyboardInputEvent? FlushPending(DateTimeOffset timestamp)
    {
        if (_pendingLeftControl is not { } pending)
        {
            return null;
        }

        _pendingLeftControl = null;
        return Normalize(pending, timestamp);
    }

    public void Reset()
    {
        _pendingLeftControl = null;
        _modifiers = ModifierState.None;
        _altGrActive = false;
        _suppressSyntheticLeftControlRelease = false;
    }

    private WindowsKeyboardInputEvent Normalize(
        RawWindowsKeyboardEvent input,
        DateTimeOffset timestamp)
    {
        var modifier = ModifierFor(input.Key.Id);
        if (modifier != ModifierState.None)
        {
            if (input.Phase == KeyPhase.Press)
            {
                _modifiers |= modifier;
            }
            else
            {
                _modifiers &= ~modifier;
            }
        }

        var altGrForEvent = _altGrActive;
        if (input.Key.Id == PhysicalKeys.RightAlt && input.Phase == KeyPhase.Release)
        {
            _altGrActive = false;
        }

        var shortcutModifiers = _modifiers & (
            ModifierState.LeftControl
            | ModifierState.RightControl
            | ModifierState.LeftAlt
            | ModifierState.RightAlt
            | ModifierState.LeftMeta
            | ModifierState.RightMeta);
        if (altGrForEvent)
        {
            shortcutModifiers &= ~ModifierState.RightAlt;
        }

        return new WindowsKeyboardInputEvent(
            input.Key,
            input.Phase,
            input.IsRepeat,
            _modifiers,
            shortcutModifiers != ModifierState.None,
            input.Origin,
            timestamp,
            input.Sequence);
    }

    private bool IsSyntheticAltGrLeftControlRelease(RawWindowsKeyboardEvent input) =>
        _suppressSyntheticLeftControlRelease
        && input.Key.Id == PhysicalKeys.LeftControl
        && input.Phase == KeyPhase.Release
        && (_modifiers & ModifierState.LeftControl) == 0;

    private static bool IsLeftControlPressCandidate(RawWindowsKeyboardEvent input) =>
        input.Key.Id == PhysicalKeys.LeftControl
        && input.ScanCodePrefix == WindowsScanCodePrefix.Base
        && input.Phase == KeyPhase.Press
        && !input.IsRepeat;

    private static bool IsAltGrPair(
        RawWindowsKeyboardEvent leftControl,
        RawWindowsKeyboardEvent rightAlt) =>
        rightAlt.Key.Id == PhysicalKeys.RightAlt
        && rightAlt.ScanCodePrefix == WindowsScanCodePrefix.E0
        && rightAlt.Phase == KeyPhase.Press
        && !rightAlt.IsRepeat
        && rightAlt.Sequence == leftControl.Sequence + 1
        && rightAlt.NativeTimestamp == leftControl.NativeTimestamp;

    private static ModifierState ModifierFor(PhysicalKeyId key) => key.Value switch
    {
        "LeftShift" => ModifierState.LeftShift,
        "RightShift" => ModifierState.RightShift,
        "LeftControl" => ModifierState.LeftControl,
        "RightControl" => ModifierState.RightControl,
        "LeftAlt" => ModifierState.LeftAlt,
        "RightAlt" => ModifierState.RightAlt,
        "LeftMeta" => ModifierState.LeftMeta,
        "RightMeta" => ModifierState.RightMeta,
        _ => ModifierState.None,
    };

    private static long ToStopwatchTicks(TimeSpan value) =>
        (long)Math.Ceiling(value.TotalSeconds * System.Diagnostics.Stopwatch.Frequency);
}
