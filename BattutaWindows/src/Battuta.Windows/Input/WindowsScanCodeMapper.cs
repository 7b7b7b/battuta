using Battuta.Core.Input;

namespace Battuta.Windows.Input;

/// <summary>
/// Maps Windows Set-1 scan-code positions to Battuta's layout-independent physical IDs.
/// Character conversion and keyboard-layout APIs are intentionally not used here.
/// </summary>
public static class WindowsScanCodeMapper
{
    public const uint VirtualKeyCancel = 0x03;
    public const uint VirtualKeyPause = 0x13;
    public const uint VirtualKeyPacket = 0xE7;

    private static readonly WindowsPhysicalKey?[] BaseTable = BuildTable(WindowsScanCodePrefix.Base);
    private static readonly WindowsPhysicalKey?[] E0Table = BuildTable(WindowsScanCodePrefix.E0);

    /// <summary>Forces table construction before low-level callbacks are installed.</summary>
    public static void WarmUp()
    {
        _ = BaseTable[1];
        _ = E0Table[1];
    }

    public static bool TryMapHookEvent(
        uint scanCode,
        bool isExtended,
        uint virtualKey,
        out WindowsScanCodePrefix prefix,
        out WindowsPhysicalKey key)
    {
        if (virtualKey == VirtualKeyPacket || scanCode is 0 or > ushort.MaxValue)
        {
            prefix = default;
            key = default;
            return false;
        }

        if (virtualKey is VirtualKeyPause or VirtualKeyCancel)
        {
            prefix = WindowsScanCodePrefix.E1;
            key = Known(PhysicalKeys.Pause);
            return true;
        }

        prefix = isExtended ? WindowsScanCodePrefix.E0 : WindowsScanCodePrefix.Base;
        return TryMap((ushort)scanCode, prefix, out key);
    }

    public static bool TryMap(
        ushort scanCode,
        WindowsScanCodePrefix prefix,
        out WindowsPhysicalKey key)
    {
        if (scanCode == 0)
        {
            key = default;
            return false;
        }

        if (prefix == WindowsScanCodePrefix.E1)
        {
            if (scanCode == 0x45)
            {
                key = Known(PhysicalKeys.Pause);
                return true;
            }

            key = default;
            return false;
        }

        var table = prefix == WindowsScanCodePrefix.E0 ? E0Table : BaseTable;
        if (scanCode < table.Length && table[scanCode] is { } mapped)
        {
            key = mapped;
            return true;
        }

        key = Unknown(scanCode, prefix);
        return true;
    }

    private static WindowsPhysicalKey?[] BuildTable(WindowsScanCodePrefix prefix)
    {
        var result = new WindowsPhysicalKey?[256];
        for (ushort scanCode = 1; scanCode < result.Length; scanCode++)
        {
            result[scanCode] = Unknown(scanCode, prefix);
        }

        if (prefix == WindowsScanCodePrefix.Base)
        {
            Add(result, 0x01, PhysicalKeys.Escape);
            AddRange(result, 0x02, [
                PhysicalKeys.Digit1, PhysicalKeys.Digit2, PhysicalKeys.Digit3,
                PhysicalKeys.Digit4, PhysicalKeys.Digit5, PhysicalKeys.Digit6,
                PhysicalKeys.Digit7, PhysicalKeys.Digit8, PhysicalKeys.Digit9,
                PhysicalKeys.Digit0]);
            Add(result, 0x0C, PhysicalKeys.Minus);
            Add(result, 0x0D, PhysicalKeys.Equal);
            Add(result, 0x0E, PhysicalKeys.Backspace);
            Add(result, 0x0F, PhysicalKeys.Tab);
            AddRange(result, 0x10, [
                PhysicalKeys.KeyQ, PhysicalKeys.KeyW, PhysicalKeys.KeyE,
                PhysicalKeys.KeyR, PhysicalKeys.KeyT, PhysicalKeys.KeyY,
                PhysicalKeys.KeyU, PhysicalKeys.KeyI, PhysicalKeys.KeyO,
                PhysicalKeys.KeyP]);
            Add(result, 0x1A, PhysicalKeys.LeftBracket);
            Add(result, 0x1B, PhysicalKeys.RightBracket);
            Add(result, 0x1C, PhysicalKeys.Enter);
            Add(result, 0x1D, PhysicalKeys.LeftControl);
            AddRange(result, 0x1E, [
                PhysicalKeys.KeyA, PhysicalKeys.KeyS, PhysicalKeys.KeyD,
                PhysicalKeys.KeyF, PhysicalKeys.KeyG, PhysicalKeys.KeyH,
                PhysicalKeys.KeyJ, PhysicalKeys.KeyK, PhysicalKeys.KeyL]);
            Add(result, 0x27, PhysicalKeys.Semicolon);
            Add(result, 0x28, PhysicalKeys.Quote);
            Add(result, 0x29, PhysicalKeys.Backquote);
            Add(result, 0x2A, PhysicalKeys.LeftShift);
            Add(result, 0x2B, PhysicalKeys.Backslash);
            AddRange(result, 0x2C, [
                PhysicalKeys.KeyZ, PhysicalKeys.KeyX, PhysicalKeys.KeyC,
                PhysicalKeys.KeyV, PhysicalKeys.KeyB, PhysicalKeys.KeyN,
                PhysicalKeys.KeyM]);
            Add(result, 0x33, PhysicalKeys.Comma);
            Add(result, 0x34, PhysicalKeys.Period);
            Add(result, 0x35, PhysicalKeys.Slash);
            Add(result, 0x36, PhysicalKeys.RightShift);
            Add(result, 0x37, PhysicalKeys.NumpadMultiply);
            Add(result, 0x38, PhysicalKeys.LeftAlt);
            Add(result, 0x39, PhysicalKeys.Space);
            Add(result, 0x3A, PhysicalKeys.CapsLock);
            AddRange(result, 0x3B, [
                PhysicalKeys.F1, PhysicalKeys.F2, PhysicalKeys.F3, PhysicalKeys.F4,
                PhysicalKeys.F5, PhysicalKeys.F6, PhysicalKeys.F7, PhysicalKeys.F8,
                PhysicalKeys.F9, PhysicalKeys.F10]);
            Add(result, 0x45, PhysicalKeys.NumLock);
            Add(result, 0x46, PhysicalKeys.ScrollLock);
            AddRange(result, 0x47, [
                PhysicalKeys.Numpad7, PhysicalKeys.Numpad8, PhysicalKeys.Numpad9,
                PhysicalKeys.NumpadSubtract, PhysicalKeys.Numpad4, PhysicalKeys.Numpad5,
                PhysicalKeys.Numpad6, PhysicalKeys.NumpadAdd, PhysicalKeys.Numpad1,
                PhysicalKeys.Numpad2, PhysicalKeys.Numpad3, PhysicalKeys.Numpad0,
                PhysicalKeys.NumpadDecimal]);
            Add(result, 0x56, PhysicalKeys.IntlBackslash);
            Add(result, 0x57, PhysicalKeys.F11);
            Add(result, 0x58, PhysicalKeys.F12);
            AddRange(result, 0x64, [
                PhysicalKeys.F13, PhysicalKeys.F14, PhysicalKeys.F15, PhysicalKeys.F16,
                PhysicalKeys.F17, PhysicalKeys.F18, PhysicalKeys.F19, PhysicalKeys.F20,
                PhysicalKeys.F21, PhysicalKeys.F22, PhysicalKeys.F23, PhysicalKeys.F24]);

            // Common Japanese 106/109-key Set-1 positions.
            Add(result, 0x70, PhysicalKeys.Kana);
            Add(result, 0x73, PhysicalKeys.IntlRo);
            Add(result, 0x7B, PhysicalKeys.Eisu);
            Add(result, 0x7D, PhysicalKeys.IntlYen);
            Add(result, 0x7E, PhysicalKeys.NumpadComma);
        }
        else
        {
            Add(result, 0x1C, PhysicalKeys.NumpadEnter);
            Add(result, 0x1D, PhysicalKeys.RightControl);
            Add(result, 0x20, PhysicalKeys.AudioVolumeMute);
            Add(result, 0x2E, PhysicalKeys.AudioVolumeDown);
            Add(result, 0x30, PhysicalKeys.AudioVolumeUp);
            Add(result, 0x35, PhysicalKeys.NumpadDivide);
            Add(result, 0x37, PhysicalKeys.PrintScreen);
            Add(result, 0x38, PhysicalKeys.RightAlt);
            Add(result, 0x47, PhysicalKeys.Home);
            Add(result, 0x48, PhysicalKeys.ArrowUp);
            Add(result, 0x49, PhysicalKeys.PageUp);
            Add(result, 0x4B, PhysicalKeys.ArrowLeft);
            Add(result, 0x4D, PhysicalKeys.ArrowRight);
            Add(result, 0x4F, PhysicalKeys.End);
            Add(result, 0x50, PhysicalKeys.ArrowDown);
            Add(result, 0x51, PhysicalKeys.PageDown);
            Add(result, 0x52, PhysicalKeys.Insert);
            Add(result, 0x53, PhysicalKeys.Delete);
            Add(result, 0x5B, PhysicalKeys.LeftMeta);
            Add(result, 0x5C, PhysicalKeys.RightMeta);
            Add(result, 0x5D, PhysicalKeys.ContextMenu);
        }

        return result;
    }

    private static void Add(
        WindowsPhysicalKey?[] destination,
        int scanCode,
        PhysicalKeyId keyId) =>
        destination[scanCode] = Known(keyId);

    private static void AddRange(
        WindowsPhysicalKey?[] destination,
        int firstScanCode,
        IReadOnlyList<PhysicalKeyId> keys)
    {
        for (var index = 0; index < keys.Count; index++)
        {
            Add(destination, firstScanCode + index, keys[index]);
        }
    }

    private static WindowsPhysicalKey Known(PhysicalKeyId id)
    {
        if (!PhysicalKeyCatalog.TryGet(id, out var definition))
        {
            return new WindowsPhysicalKey(id, KeyboardRowId.R4, null, false, true);
        }

        return new WindowsPhysicalKey(
            id,
            definition.Row,
            definition.SpecialKey,
            definition.IsAssignable,
            true);
    }

    private static WindowsPhysicalKey Unknown(
        ushort scanCode,
        WindowsScanCodePrefix prefix)
    {
        var namespacePart = prefix == WindowsScanCodePrefix.E0 ? "e0" : "base";
        return new WindowsPhysicalKey(
            new PhysicalKeyId($"win.scan.{namespacePart}.{scanCode:X4}"),
            KeyboardRowId.R4,
            null,
            false,
            false);
    }
}
