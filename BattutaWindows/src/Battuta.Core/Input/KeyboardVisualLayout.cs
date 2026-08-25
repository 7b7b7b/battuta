namespace Battuta.Core.Input;

public enum KeyboardVisualVerticalSlot
{
    Full,
    UpperHalf,
    LowerHalf,
}

public sealed record KeyboardVisualPlacement(
    string Id,
    PhysicalKeyId? KeyId,
    string Label,
    string? IconKey,
    int Row,
    double XUnits,
    double WidthUnits,
    KeyboardVisualVerticalSlot VerticalSlot);

public sealed record KeyboardVisualLayout(
    string Id,
    double WidthUnits,
    int RowCount,
    IReadOnlyList<KeyboardVisualPlacement> Placements)
{
    public IReadOnlySet<PhysicalKeyId> KeyIds { get; } = Placements
        .Where(placement => placement.KeyId.HasValue)
        .Select(placement => placement.KeyId!.Value)
        .ToHashSet();

    public IReadOnlyList<KeyboardVisualPlacement> PlacementsInRow(int row) =>
        Placements.Where(placement => placement.Row == row).ToArray();
}

/// <summary>Exact 14.5U compact Magic Keyboard geometry used by the macOS UI.</summary>
public static class KeyboardVisualLayoutCatalog
{
    public static KeyboardVisualLayout MagicKeyboardAnsi { get; } = BuildMagicKeyboardAnsi();

    private static KeyboardVisualLayout BuildMagicKeyboardAnsi()
    {
        var rows = new Slot[][]
        {
            [
                Key(PhysicalKeys.Escape, 1.5),
                Key(PhysicalKeys.F1), Key(PhysicalKeys.F2), Key(PhysicalKeys.F3), Key(PhysicalKeys.F4),
                Key(PhysicalKeys.F5), Key(PhysicalKeys.F6), Key(PhysicalKeys.F7), Key(PhysicalKeys.F8),
                Key(PhysicalKeys.F9), Key(PhysicalKeys.F10), Key(PhysicalKeys.F11), Key(PhysicalKeys.F12),
                Decoration("lock", "锁定", "lock.fill"),
            ],
            [
                Key(PhysicalKeys.Backquote),
                Key(PhysicalKeys.Digit1), Key(PhysicalKeys.Digit2), Key(PhysicalKeys.Digit3),
                Key(PhysicalKeys.Digit4), Key(PhysicalKeys.Digit5), Key(PhysicalKeys.Digit6),
                Key(PhysicalKeys.Digit7), Key(PhysicalKeys.Digit8), Key(PhysicalKeys.Digit9),
                Key(PhysicalKeys.Digit0), Key(PhysicalKeys.Minus), Key(PhysicalKeys.Equal),
                Key(PhysicalKeys.Backspace, 1.5),
            ],
            [
                Key(PhysicalKeys.Tab, 1.5),
                Key(PhysicalKeys.KeyQ), Key(PhysicalKeys.KeyW), Key(PhysicalKeys.KeyE),
                Key(PhysicalKeys.KeyR), Key(PhysicalKeys.KeyT), Key(PhysicalKeys.KeyY),
                Key(PhysicalKeys.KeyU), Key(PhysicalKeys.KeyI), Key(PhysicalKeys.KeyO),
                Key(PhysicalKeys.KeyP), Key(PhysicalKeys.LeftBracket),
                Key(PhysicalKeys.RightBracket), Key(PhysicalKeys.Backslash),
            ],
            [
                Key(PhysicalKeys.CapsLock, 1.75),
                Key(PhysicalKeys.KeyA), Key(PhysicalKeys.KeyS), Key(PhysicalKeys.KeyD),
                Key(PhysicalKeys.KeyF), Key(PhysicalKeys.KeyG), Key(PhysicalKeys.KeyH),
                Key(PhysicalKeys.KeyJ), Key(PhysicalKeys.KeyK), Key(PhysicalKeys.KeyL),
                Key(PhysicalKeys.Semicolon), Key(PhysicalKeys.Quote),
                Key(PhysicalKeys.Enter, 1.75),
            ],
            [
                Key(PhysicalKeys.LeftShift, 2.25),
                Key(PhysicalKeys.KeyZ), Key(PhysicalKeys.KeyX), Key(PhysicalKeys.KeyC),
                Key(PhysicalKeys.KeyV), Key(PhysicalKeys.KeyB), Key(PhysicalKeys.KeyN),
                Key(PhysicalKeys.KeyM), Key(PhysicalKeys.Comma), Key(PhysicalKeys.Period),
                Key(PhysicalKeys.Slash), Key(PhysicalKeys.RightShift, 2.25),
            ],
            [
                Key(PhysicalKeys.Fn), Key(PhysicalKeys.LeftControl), Key(PhysicalKeys.LeftAlt),
                Key(PhysicalKeys.LeftMeta, 1.25), Key(PhysicalKeys.Space, 5),
                Key(PhysicalKeys.RightMeta, 1.25), Key(PhysicalKeys.RightAlt),
                Key(PhysicalKeys.ArrowLeft),
                Stacked(PhysicalKeys.ArrowUp, PhysicalKeys.ArrowDown),
                Key(PhysicalKeys.ArrowRight),
            ],
        };

        var placements = new List<KeyboardVisualPlacement>(78);
        for (var row = 0; row < rows.Length; row++)
        {
            var x = 0d;
            foreach (var slot in rows[row])
            {
                switch (slot)
                {
                    case KeySlot key:
                        placements.Add(Placement(key.KeyId, row, x, key.Width, KeyboardVisualVerticalSlot.Full));
                        break;
                    case StackedSlot stacked:
                        placements.Add(Placement(stacked.Upper, row, x, stacked.Width, KeyboardVisualVerticalSlot.UpperHalf));
                        placements.Add(Placement(stacked.Lower, row, x, stacked.Width, KeyboardVisualVerticalSlot.LowerHalf));
                        break;
                    case DecorationSlot decoration:
                        placements.Add(new KeyboardVisualPlacement(
                            $"decoration.{decoration.Id}", null, decoration.Label, decoration.IconKey,
                            row, x, decoration.Width, KeyboardVisualVerticalSlot.Full));
                        break;
                }

                x += slot.Width;
            }

            if (Math.Abs(x - 14.5) > 0.0001)
            {
                throw new InvalidOperationException($"Keyboard visual row {row} must span 14.5U.");
            }
        }

        return new KeyboardVisualLayout(
            "apple-magic-keyboard-us-ansi-2024",
            14.5,
            rows.Length,
            placements);
    }

    private static KeyboardVisualPlacement Placement(
        PhysicalKeyId keyId,
        int row,
        double x,
        double width,
        KeyboardVisualVerticalSlot slot)
    {
        var label = PhysicalKeyCatalog.TryGet(keyId, out var definition)
            ? definition.Label
            : keyId.Value;
        return new KeyboardVisualPlacement(
            $"key.{keyId.Value}", keyId, label, null, row, x, width, slot);
    }

    private static KeySlot Key(PhysicalKeyId id, double width = 1) => new(id, width);
    private static StackedSlot Stacked(PhysicalKeyId upper, PhysicalKeyId lower, double width = 1) =>
        new(upper, lower, width);
    private static DecorationSlot Decoration(string id, string label, string iconKey, double width = 1) =>
        new(id, label, iconKey, width);

    private abstract record Slot(double Width);
    private sealed record KeySlot(PhysicalKeyId KeyId, double KeyWidth) : Slot(KeyWidth);
    private sealed record StackedSlot(PhysicalKeyId Upper, PhysicalKeyId Lower, double StackWidth) : Slot(StackWidth);
    private sealed record DecorationSlot(string Id, string Label, string IconKey, double DecorationWidth)
        : Slot(DecorationWidth);
}
