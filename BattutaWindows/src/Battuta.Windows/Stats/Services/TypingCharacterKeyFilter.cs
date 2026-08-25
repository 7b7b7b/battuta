using Battuta.Core.Input;

namespace Battuta.Windows.Stats.Services;

/// <summary>
/// Classifies physical keys that can directly contribute one text character.
/// This intentionally never asks Windows to translate a key into text.
/// </summary>
public static class TypingCharacterKeyFilter
{
    private static readonly HashSet<PhysicalKeyId> CharacterKeys =
    [
        PhysicalKeys.KeyA, PhysicalKeys.KeyB, PhysicalKeys.KeyC, PhysicalKeys.KeyD,
        PhysicalKeys.KeyE, PhysicalKeys.KeyF, PhysicalKeys.KeyG, PhysicalKeys.KeyH,
        PhysicalKeys.KeyI, PhysicalKeys.KeyJ, PhysicalKeys.KeyK, PhysicalKeys.KeyL,
        PhysicalKeys.KeyM, PhysicalKeys.KeyN, PhysicalKeys.KeyO, PhysicalKeys.KeyP,
        PhysicalKeys.KeyQ, PhysicalKeys.KeyR, PhysicalKeys.KeyS, PhysicalKeys.KeyT,
        PhysicalKeys.KeyU, PhysicalKeys.KeyV, PhysicalKeys.KeyW, PhysicalKeys.KeyX,
        PhysicalKeys.KeyY, PhysicalKeys.KeyZ,
        PhysicalKeys.Digit0, PhysicalKeys.Digit1, PhysicalKeys.Digit2,
        PhysicalKeys.Digit3, PhysicalKeys.Digit4, PhysicalKeys.Digit5,
        PhysicalKeys.Digit6, PhysicalKeys.Digit7, PhysicalKeys.Digit8,
        PhysicalKeys.Digit9,
        PhysicalKeys.Backquote, PhysicalKeys.Minus, PhysicalKeys.Equal,
        PhysicalKeys.LeftBracket, PhysicalKeys.RightBracket, PhysicalKeys.Backslash,
        PhysicalKeys.Semicolon, PhysicalKeys.Quote, PhysicalKeys.Comma,
        PhysicalKeys.Period, PhysicalKeys.Slash, PhysicalKeys.Space,
        PhysicalKeys.Numpad0, PhysicalKeys.Numpad1, PhysicalKeys.Numpad2,
        PhysicalKeys.Numpad3, PhysicalKeys.Numpad4, PhysicalKeys.Numpad5,
        PhysicalKeys.Numpad6, PhysicalKeys.Numpad7, PhysicalKeys.Numpad8,
        PhysicalKeys.Numpad9, PhysicalKeys.NumpadDecimal, PhysicalKeys.NumpadDivide,
        PhysicalKeys.NumpadMultiply, PhysicalKeys.NumpadSubtract, PhysicalKeys.NumpadAdd,
        PhysicalKeys.NumpadEqual, PhysicalKeys.NumpadComma,
        PhysicalKeys.IntlBackslash, PhysicalKeys.IntlYen, PhysicalKeys.IntlRo,
    ];

    public static bool CountsAsCharacter(PhysicalKeyId key, bool isShortcutModified) =>
        !isShortcutModified && CharacterKeys.Contains(key);
}
