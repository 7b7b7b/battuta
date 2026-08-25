using System.Diagnostics;
using Battuta.Core.Input;
using Battuta.Windows.Input;

namespace Battuta.Windows.Tests.Input;

public sealed class WindowsKeyboardEventNormalizerTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 24, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void RepeatTrackerMatchesMacPhysicalPressSemantics()
    {
        var tracker = new WindowsKeyboardRepeatTracker();

        Assert.False(tracker.Observe(PhysicalKeys.KeyA, KeyPhase.Press));
        Assert.True(tracker.Observe(PhysicalKeys.KeyA, KeyPhase.Press));
        Assert.False(tracker.Observe(PhysicalKeys.KeyA, KeyPhase.Release));
        Assert.False(tracker.Observe(PhysicalKeys.KeyA, KeyPhase.Press));

        tracker.Reset();
        Assert.False(tracker.Observe(PhysicalKeys.KeyA, KeyPhase.Press));
    }

    [Fact]
    public void AltGrSuppressesSyntheticControlAndDoesNotMarkCharactersAsShortcuts()
    {
        var normalizer = new WindowsKeyboardEventNormalizer();
        var control = Raw(PhysicalKeys.LeftControl, WindowsScanCodePrefix.Base, 0x1D, KeyPhase.Press, 1, 100);
        var rightAlt = Raw(PhysicalKeys.RightAlt, WindowsScanCodePrefix.E0, 0x38, KeyPhase.Press, 2, 100);

        Assert.Equal(0, normalizer.Process(control, Now).Count);
        var altResult = normalizer.Process(rightAlt, Now);
        Assert.Equal(1, altResult.Count);
        Assert.Equal(PhysicalKeys.RightAlt, altResult.First.Key.Id);
        Assert.False(altResult.First.IsShortcutModified);
        Assert.Equal(ModifierState.RightAlt, altResult.First.Modifiers);

        var character = normalizer.Process(
            Raw(PhysicalKeys.KeyQ, WindowsScanCodePrefix.Base, 0x10, KeyPhase.Press, 3, 101),
            Now);
        Assert.Equal(1, character.Count);
        Assert.False(character.First.IsShortcutModified);
        Assert.Equal(ModifierState.RightAlt, character.First.Modifiers);

        var altRelease = normalizer.Process(
            Raw(PhysicalKeys.RightAlt, WindowsScanCodePrefix.E0, 0x38, KeyPhase.Release, 4, 102),
            Now);
        Assert.Equal(1, altRelease.Count);
        Assert.Equal(ModifierState.None, altRelease.First.Modifiers);

        var controlRelease = normalizer.Process(
            Raw(PhysicalKeys.LeftControl, WindowsScanCodePrefix.Base, 0x1D, KeyPhase.Release, 5, 102),
            Now);
        Assert.Equal(0, controlRelease.Count);
    }

    [Fact]
    public void NonAdjacentOrDifferentlyTimedControlIsGenuine()
    {
        var normalizer = new WindowsKeyboardEventNormalizer();
        var control = Raw(PhysicalKeys.LeftControl, WindowsScanCodePrefix.Base, 0x1D, KeyPhase.Press, 1, 100);
        var character = Raw(PhysicalKeys.KeyA, WindowsScanCodePrefix.Base, 0x1E, KeyPhase.Press, 2, 101);

        Assert.Equal(0, normalizer.Process(control, Now).Count);
        var result = normalizer.Process(character, Now);

        Assert.Equal(2, result.Count);
        Assert.Equal(PhysicalKeys.LeftControl, result.First.Key.Id);
        Assert.True(result.First.IsShortcutModified);
        Assert.Equal(PhysicalKeys.KeyA, result.Second.Key.Id);
        Assert.True(result.Second.IsShortcutModified);
    }

    [Fact]
    public void GenuineControlHeldBeforeRightAltRemainsAShortcut()
    {
        var normalizer = new WindowsKeyboardEventNormalizer();
        _ = normalizer.Process(
            Raw(PhysicalKeys.LeftControl, WindowsScanCodePrefix.Base, 0x1D, KeyPhase.Press, 1, 100),
            Now);
        var flushed = normalizer.FlushPending(Now);
        Assert.NotNull(flushed);

        var rightAlt = normalizer.Process(
            Raw(PhysicalKeys.RightAlt, WindowsScanCodePrefix.E0, 0x38, KeyPhase.Press, 2, 120),
            Now);
        Assert.True(rightAlt.First.IsShortcutModified);

        var character = normalizer.Process(
            Raw(PhysicalKeys.KeyQ, WindowsScanCodePrefix.Base, 0x10, KeyPhase.Press, 3, 121),
            Now);
        Assert.True(character.First.IsShortcutModified);
    }

    [Theory]
    [InlineData("LeftAlt")]
    [InlineData("RightAlt")]
    [InlineData("LeftControl")]
    [InlineData("RightControl")]
    [InlineData("LeftMeta")]
    [InlineData("RightMeta")]
    public void GenuineWindowsShortcutModifiersAreExplicit(string keyName)
    {
        var key = PhysicalKeyCatalog.All.Single(definition => definition.Id.Value == keyName).Id;
        var (prefix, scanCode) = keyName switch
        {
            "LeftAlt" => (WindowsScanCodePrefix.Base, (ushort)0x38),
            "RightAlt" => (WindowsScanCodePrefix.E0, (ushort)0x38),
            "LeftControl" => (WindowsScanCodePrefix.Base, (ushort)0x1D),
            "RightControl" => (WindowsScanCodePrefix.E0, (ushort)0x1D),
            "LeftMeta" => (WindowsScanCodePrefix.E0, (ushort)0x5B),
            _ => (WindowsScanCodePrefix.E0, (ushort)0x5C),
        };
        var normalizer = new WindowsKeyboardEventNormalizer();
        var result = normalizer.Process(Raw(key, prefix, scanCode, KeyPhase.Press, 1, 100), Now);
        var value = result.Count == 0 ? normalizer.FlushPending(Now) : result.First;

        Assert.NotNull(value);
        Assert.True(value.Value.IsShortcutModified);
    }

    [Theory]
    [InlineData("LeftShift", 0x2A)]
    [InlineData("RightShift", 0x36)]
    public void ShiftDoesNotTurnCharacterInputIntoAShortcut(string keyName, ushort scanCode)
    {
        var key = PhysicalKeyCatalog.All.Single(definition => definition.Id.Value == keyName).Id;
        var normalizer = new WindowsKeyboardEventNormalizer();

        var shift = normalizer.Process(
            Raw(key, WindowsScanCodePrefix.Base, scanCode, KeyPhase.Press, 1, 100),
            Now);
        Assert.False(shift.First.IsShortcutModified);

        var character = normalizer.Process(
            Raw(PhysicalKeys.KeyA, WindowsScanCodePrefix.Base, 0x1E, KeyPhase.Press, 2, 101),
            Now);
        Assert.False(character.First.IsShortcutModified);
    }

    [Fact]
    public void ResetClearsPendingAndModifierState()
    {
        var normalizer = new WindowsKeyboardEventNormalizer();
        _ = normalizer.Process(
            Raw(PhysicalKeys.LeftControl, WindowsScanCodePrefix.Base, 0x1D, KeyPhase.Press, 1, 100),
            Now);
        normalizer.Reset();

        Assert.False(normalizer.HasPendingEvent);
        Assert.Equal(ModifierState.None, normalizer.Modifiers);
        var character = normalizer.Process(
            Raw(PhysicalKeys.KeyA, WindowsScanCodePrefix.Base, 0x1E, KeyPhase.Press, 2, 101),
            Now);
        Assert.False(character.First.IsShortcutModified);
    }

    private static RawWindowsKeyboardEvent Raw(
        PhysicalKeyId keyId,
        WindowsScanCodePrefix prefix,
        ushort scanCode,
        KeyPhase phase,
        ulong sequence,
        uint nativeTimestamp)
    {
        Assert.True(PhysicalKeyCatalog.TryGet(keyId, out var definition));
        return new RawWindowsKeyboardEvent(
            new WindowsPhysicalKey(
                keyId,
                definition.Row,
                definition.SpecialKey,
                definition.IsAssignable,
                true),
            prefix,
            scanCode,
            phase,
            false,
            WindowsInputOrigin.Hardware,
            nativeTimestamp,
            Stopwatch.GetTimestamp(),
            sequence);
    }
}
