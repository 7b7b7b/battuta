using Battuta.Core.Input;
using Battuta.Core.SoundPacks;

namespace Battuta.Core.Tests.Input;

public sealed class PhysicalKeyCatalogTests
{
    [Fact]
    public void StableAndLegacyIdsAreUnique()
    {
        Assert.Equal(
            PhysicalKeyCatalog.All.Count,
            PhysicalKeyCatalog.All.Select(key => key.Id.Value).Distinct(StringComparer.Ordinal).Count());
        Assert.Equal(
            PhysicalKeyCatalog.All.Count(key => key.LegacySoundPackV1Id is not null),
            PhysicalKeyCatalog.All
                .Select(key => key.LegacySoundPackV1Id)
                .Where(id => id is not null)
                .Distinct(StringComparer.Ordinal)
                .Count());
    }

    [Fact]
    public void PortedLayoutsRetainMacCompatibilityCounts()
    {
        Assert.Equal("mac-ansi-tkl-v1", KeyboardLayoutCatalog.DefaultLayoutId);
        Assert.Equal(78, PhysicalKeyCatalog.CompactKeys.Count);
        Assert.Equal(41, PhysicalKeyCatalog.ExtendedKeys.Count);
        Assert.Equal(6, KeyboardLayoutCatalog.CompactAnsi.Rows.Count);
    }

    [Theory]
    [InlineData("Backquote", KeyboardRowId.R0)]
    [InlineData("Digit5", KeyboardRowId.R0)]
    [InlineData("KeyQ", KeyboardRowId.R1)]
    [InlineData("KeyA", KeyboardRowId.R2)]
    [InlineData("KeyZ", KeyboardRowId.R3)]
    [InlineData("Tab", KeyboardRowId.R4)]
    [InlineData("CapsLock", KeyboardRowId.R4)]
    [InlineData("LeftShift", KeyboardRowId.R4)]
    [InlineData("Space", KeyboardRowId.R4)]
    public void RowsMatchMacSoundMapping(string stableId, KeyboardRowId expectedRow)
    {
        Assert.True(PhysicalKeyCatalog.TryGetByStableId(stableId, out var definition));
        Assert.Equal(expectedRow, definition.Row);
    }

    [Theory]
    [InlineData("Space", KeyboardSpecialKeyId.Space)]
    [InlineData("Enter", KeyboardSpecialKeyId.Enter)]
    [InlineData("NumpadEnter", KeyboardSpecialKeyId.Enter)]
    [InlineData("Backspace", KeyboardSpecialKeyId.Backspace)]
    [InlineData("Delete", KeyboardSpecialKeyId.Backspace)]
    public void SpecialKeysRetainCrossPlatformMeaning(
        string stableId,
        KeyboardSpecialKeyId expectedSpecial)
    {
        Assert.True(PhysicalKeyCatalog.TryGetByStableId(stableId, out var definition));
        Assert.Equal(expectedSpecial, definition.SpecialKey);
    }

    [Fact]
    public void LeftAndRightModifiersRemainDistinct()
    {
        Assert.NotEqual(PhysicalKeys.LeftShift, PhysicalKeys.RightShift);
        Assert.NotEqual(PhysicalKeys.LeftControl, PhysicalKeys.RightControl);
        Assert.NotEqual(PhysicalKeys.LeftAlt, PhysicalKeys.RightAlt);
        Assert.NotEqual(PhysicalKeys.LeftMeta, PhysicalKeys.RightMeta);
    }

    [Fact]
    public void NamespacedUnknownKeyCanBePersistedWithoutJoiningDiyCatalog()
    {
        var unknown = new PhysicalKeyId("win.scan.e0.005E");

        Assert.Equal("win.scan.e0.005E", unknown.Value);
        Assert.False(PhysicalKeyCatalog.TryGet(unknown, out _));
        Assert.False(SoundPackV1KeyCompatibility.TryGetLegacyId(unknown, out _));
        Assert.Equal(KeyboardRowId.R4, PhysicalKeyCatalog.RowFor(unknown));
    }

    [Fact]
    public void MagicKeyboardGeometryMatchesMacViewContract()
    {
        var layout = KeyboardVisualLayoutCatalog.MagicKeyboardAnsi;

        Assert.Equal(14.5, layout.WidthUnits);
        Assert.Equal(6, layout.RowCount);
        Assert.Equal(78, layout.Placements.Count);
        Assert.Equal(78, layout.Placements.Select(placement => placement.Id).Distinct().Count());
        Assert.Equal(77, layout.KeyIds.Count);
        Assert.Equal(
            [PhysicalKeys.RightControl],
            PhysicalKeyCatalog.CompactKeys.Select(key => key.Id).Except(layout.KeyIds));

        var up = Assert.Single(layout.Placements, placement => placement.KeyId == PhysicalKeys.ArrowUp);
        var down = Assert.Single(layout.Placements, placement => placement.KeyId == PhysicalKeys.ArrowDown);
        Assert.Equal(KeyboardVisualVerticalSlot.UpperHalf, up.VerticalSlot);
        Assert.Equal(KeyboardVisualVerticalSlot.LowerHalf, down.VerticalSlot);
        Assert.Equal((up.Row, up.XUnits, up.WidthUnits), (down.Row, down.XUnits, down.WidthUnits));

        foreach (var row in Enumerable.Range(0, layout.RowCount))
        {
            var columns = layout.PlacementsInRow(row).GroupBy(placement => placement.XUnits);
            Assert.Equal(14.5, columns.Sum(column => column.Select(item => item.WidthUnits).Distinct().Single()), 4);
        }
    }

    [Theory]
    [InlineData("KeyA", "a")]
    [InlineData("LeftAlt", "leftOption")]
    [InlineData("RightAlt", "rightOption")]
    [InlineData("LeftMeta", "leftCommand")]
    [InlineData("RightMeta", "rightCommand")]
    [InlineData("Fn", "function")]
    [InlineData("ArrowLeft", "leftArrow")]
    [InlineData("NumpadEnter", "extended.keypadEnter")]
    [InlineData("Delete", "extended.forwardDelete")]
    [InlineData("Insert", "extended.help")]
    [InlineData("NumLock", "extended.keypadClear")]
    public void LegacySoundPackIdsRoundTrip(string stableId, string legacyId)
    {
        Assert.True(PhysicalKeyCatalog.TryGetByStableId(stableId, out var definition));
        Assert.True(SoundPackV1KeyCompatibility.TryGetLegacyId(definition.Id, out var encoded));
        Assert.Equal(legacyId, encoded);
        Assert.True(SoundPackV1KeyCompatibility.TryGetPhysicalKey(legacyId, out var decoded));
        Assert.Equal(definition.Id, decoded);
    }
}
