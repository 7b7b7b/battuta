namespace Battuta.Core.Input;

public enum KeyPhase
{
    Press,
    Release,
}

[Flags]
public enum ModifierState
{
    None = 0,
    LeftShift = 1 << 0,
    RightShift = 1 << 1,
    LeftControl = 1 << 2,
    RightControl = 1 << 3,
    LeftAlt = 1 << 4,
    RightAlt = 1 << 5,
    LeftMeta = 1 << 6,
    RightMeta = 1 << 7,
}

public readonly record struct KeyboardInputEvent(
    PhysicalKeyId Key,
    KeyPhase Phase,
    bool IsRepeat,
    ModifierState Modifiers,
    DateTimeOffset Timestamp);
