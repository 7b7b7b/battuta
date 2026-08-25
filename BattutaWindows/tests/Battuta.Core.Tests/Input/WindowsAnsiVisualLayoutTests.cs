using Battuta.Core.Input;
using Battuta.Core.SoundPacks;

namespace Battuta.Core.Tests.Input;

public sealed class WindowsAnsiVisualLayoutTests
{
    [Fact]
    public void CompactLayoutHasStablePhysicalIdentityForEveryVisualKey()
    {
        var layout = WindowsAnsiVisualLayoutCatalog.CompactAnsi;

        Assert.Equal("windows-ansi-compact-14.5u-v1", layout.Id);
        Assert.Equal(14.5, layout.WidthUnits);
        Assert.Equal(6, layout.RowCount);
        Assert.Equal(78, layout.Placements.Count);
        Assert.All(layout.Placements, placement => Assert.True(placement.KeyId.HasValue));
        Assert.Equal(
            layout.Placements.Count,
            layout.Placements.Select(placement => placement.KeyId).Distinct().Count());
        Assert.Equal(
            layout.Placements.Count,
            layout.Placements.Select(placement => placement.Id).Distinct(StringComparer.Ordinal).Count());
    }

    [Fact]
    public void EveryVisualRowIsContiguousAndSpansFourteenAndAHalfUnits()
    {
        var layout = WindowsAnsiVisualLayoutCatalog.CompactAnsi;
        const double tolerance = 0.0001;

        for (var row = 0; row < layout.RowCount; row++)
        {
            var columns = layout.PlacementsInRow(row)
                .GroupBy(placement => placement.XUnits)
                .OrderBy(column => column.Key)
                .ToArray();
            var cursor = 0d;
            foreach (var column in columns)
            {
                var width = Assert.Single(column.Select(item => item.WidthUnits).Distinct());
                Assert.InRange(Math.Abs(column.Key - cursor), 0, tolerance);
                cursor = column.Key + width;
            }

            Assert.InRange(Math.Abs(cursor - layout.WidthUnits), 0, tolerance);
        }
    }

    [Theory]
    [MemberData(nameof(WindowsLabels))]
    public void DisplayAdapterUsesWindowsTerminology(PhysicalKeyId key, string expectedLabel)
    {
        Assert.Equal(expectedLabel, WindowsKeyDisplayCatalog.LabelFor(key));
    }

    public static TheoryData<PhysicalKeyId, string> WindowsLabels => new()
    {
        { PhysicalKeys.Escape, "Esc" },
        { PhysicalKeys.Backspace, "Backspace" },
        { PhysicalKeys.Enter, "Enter" },
        { PhysicalKeys.LeftControl, "Ctrl" },
        { PhysicalKeys.RightControl, "Ctrl" },
        { PhysicalKeys.LeftMeta, "Win" },
        { PhysicalKeys.RightMeta, "Win" },
        { PhysicalKeys.LeftAlt, "Alt" },
        { PhysicalKeys.RightAlt, "Alt" },
        { PhysicalKeys.Insert, "Insert" },
        { PhysicalKeys.Delete, "Delete" },
        { PhysicalKeys.NumLock, "Num Lock" },
        { PhysicalKeys.PrintScreen, "Print Screen" },
        { PhysicalKeys.ScrollLock, "Scroll Lock" },
        { PhysicalKeys.ContextMenu, "Menu" },
        { PhysicalKeys.NumpadEnter, "Num Enter" },
    };

    [Fact]
    public void LeftAndRightModifiersUseDistinctIdsEvenWhenKeycapLabelsMatch()
    {
        var ids = WindowsAnsiVisualLayoutCatalog.CompactAnsi.KeyIds;

        Assert.Contains(PhysicalKeys.LeftShift, ids);
        Assert.Contains(PhysicalKeys.RightShift, ids);
        Assert.Contains(PhysicalKeys.LeftControl, ids);
        Assert.Contains(PhysicalKeys.RightControl, ids);
        Assert.Contains(PhysicalKeys.LeftAlt, ids);
        Assert.Contains(PhysicalKeys.RightAlt, ids);
        Assert.Contains(PhysicalKeys.LeftMeta, ids);
        Assert.Contains(PhysicalKeys.RightMeta, ids);
        Assert.NotEqual(PhysicalKeys.LeftShift, PhysicalKeys.RightShift);
        Assert.NotEqual(PhysicalKeys.LeftControl, PhysicalKeys.RightControl);
        Assert.NotEqual(PhysicalKeys.LeftAlt, PhysicalKeys.RightAlt);
        Assert.NotEqual(PhysicalKeys.LeftMeta, PhysicalKeys.RightMeta);
    }

    [Fact]
    public void StandardLayoutReplacesDeviceSpecificFnWithWindowsKeys()
    {
        var ids = WindowsAnsiVisualLayoutCatalog.CompactAnsi.KeyIds;

        Assert.DoesNotContain(PhysicalKeys.Fn, ids);
        Assert.Contains(PhysicalKeys.PrintScreen, ids);
        Assert.Contains(PhysicalKeys.RightControl, ids);
        Assert.False(WindowsAnsiVisualLayoutCatalog.DeviceSpecificFn.IsUniversallyObservable);
        Assert.True(WindowsAnsiVisualLayoutCatalog.DeviceSpecificFn.IsDiyAssignable);
        Assert.Equal("Fn", WindowsAnsiVisualLayoutCatalog.DeviceSpecificFn.Label);
    }

    [Theory]
    [InlineData("Digit1", KeyboardRowId.R0)]
    [InlineData("KeyQ", KeyboardRowId.R1)]
    [InlineData("KeyA", KeyboardRowId.R2)]
    [InlineData("KeyZ", KeyboardRowId.R3)]
    [InlineData("Backspace", KeyboardRowId.R4)]
    [InlineData("Tab", KeyboardRowId.R4)]
    [InlineData("LeftShift", KeyboardRowId.R4)]
    [InlineData("Space", KeyboardRowId.R4)]
    [InlineData("PrintScreen", KeyboardRowId.R4)]
    public void VisualKeysKeepCoreSoundRows(string stableId, KeyboardRowId expectedRow)
    {
        Assert.True(PhysicalKeyCatalog.TryGetByStableId(stableId, out var key));
        Assert.Equal(expectedRow, WindowsKeyDisplayCatalog.Get(key.Id).SoundRow);
    }

    [Fact]
    public void ExtendedCatalogIsUniqueCompleteAndExcludesFn()
    {
        var extended = WindowsAnsiVisualLayoutCatalog.ExtendedKeys;

        Assert.Equal(48, extended.Count);
        Assert.Equal(48, extended.Select(key => key.Id).Distinct().Count());
        Assert.DoesNotContain(extended, key => key.Id == PhysicalKeys.Fn);
        Assert.Contains(extended, key => key.Id == PhysicalKeys.Insert && key.Label == "Insert");
        Assert.Contains(extended, key => key.Id == PhysicalKeys.Delete && key.Label == "Delete");
        Assert.Contains(extended, key => key.Id == PhysicalKeys.NumLock && key.Label == "Num Lock");
        Assert.Contains(extended, key => key.Id == PhysicalKeys.ScrollLock && key.Label == "Scroll Lock");
        Assert.Contains(extended, key => key.Id == PhysicalKeys.Pause && key.Label == "Pause");
        Assert.Contains(extended, key => key.Id == PhysicalKeys.ContextMenu && key.Label == "Menu");
        foreach (var number in Enumerable.Range(13, 12))
        {
            Assert.Contains(extended, key => key.Id.Value == $"F{number}");
        }
    }

    [Fact]
    public void LegacySchemaAndMacVisualCatalogRemainUnchanged()
    {
        Assert.Equal("mac-ansi-tkl-v1", KeyboardLayoutCatalog.DefaultLayoutId);
        Assert.Equal("apple-magic-keyboard-us-ansi-2024", KeyboardVisualLayoutCatalog.MagicKeyboardAnsi.Id);
        Assert.Contains(
            KeyboardVisualLayoutCatalog.MagicKeyboardAnsi.Placements,
            placement => placement.Id == "decoration.lock" && placement.KeyId is null);

        Assert.True(SoundPackV1KeyCompatibility.TryGetLegacyId(
            PhysicalKeys.LeftAlt,
            out var leftAlt));
        Assert.Equal("leftOption", leftAlt);
        Assert.True(SoundPackV1KeyCompatibility.TryGetLegacyId(
            PhysicalKeys.LeftMeta,
            out var leftMeta));
        Assert.Equal("leftCommand", leftMeta);
        Assert.True(SoundPackV1KeyCompatibility.TryGetLegacyId(
            PhysicalKeys.Insert,
            out var insert));
        Assert.Equal("extended.help", insert);
        Assert.True(SoundPackV1KeyCompatibility.TryGetLegacyId(
            PhysicalKeys.Delete,
            out var delete));
        Assert.Equal("extended.forwardDelete", delete);
        Assert.True(SoundPackV1KeyCompatibility.TryGetLegacyId(
            PhysicalKeys.NumLock,
            out var numLock));
        Assert.Equal("extended.keypadClear", numLock);
    }
}
