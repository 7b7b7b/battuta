using Battuta.Core.Input;
using Battuta.Windows.Input;

namespace Battuta.Windows.Tests.Input;

public sealed class WindowsScanCodeMapperTests
{
    [Theory]
    [InlineData(0x1C, WindowsScanCodePrefix.Base, "Enter")]
    [InlineData(0x1C, WindowsScanCodePrefix.E0, "NumpadEnter")]
    [InlineData(0x1D, WindowsScanCodePrefix.Base, "LeftControl")]
    [InlineData(0x1D, WindowsScanCodePrefix.E0, "RightControl")]
    [InlineData(0x35, WindowsScanCodePrefix.Base, "Slash")]
    [InlineData(0x35, WindowsScanCodePrefix.E0, "NumpadDivide")]
    [InlineData(0x37, WindowsScanCodePrefix.Base, "NumpadMultiply")]
    [InlineData(0x37, WindowsScanCodePrefix.E0, "PrintScreen")]
    [InlineData(0x38, WindowsScanCodePrefix.Base, "LeftAlt")]
    [InlineData(0x38, WindowsScanCodePrefix.E0, "RightAlt")]
    [InlineData(0x47, WindowsScanCodePrefix.Base, "Numpad7")]
    [InlineData(0x47, WindowsScanCodePrefix.E0, "Home")]
    [InlineData(0x48, WindowsScanCodePrefix.Base, "Numpad8")]
    [InlineData(0x48, WindowsScanCodePrefix.E0, "ArrowUp")]
    [InlineData(0x4B, WindowsScanCodePrefix.Base, "Numpad4")]
    [InlineData(0x4B, WindowsScanCodePrefix.E0, "ArrowLeft")]
    [InlineData(0x4D, WindowsScanCodePrefix.Base, "Numpad6")]
    [InlineData(0x4D, WindowsScanCodePrefix.E0, "ArrowRight")]
    [InlineData(0x50, WindowsScanCodePrefix.Base, "Numpad2")]
    [InlineData(0x50, WindowsScanCodePrefix.E0, "ArrowDown")]
    public void MapsAmbiguousSetOnePositionsByPrefix(
        ushort scanCode,
        WindowsScanCodePrefix prefix,
        string expectedId)
    {
        Assert.True(WindowsScanCodeMapper.TryMap(scanCode, prefix, out var key));
        Assert.Equal(expectedId, key.Id.Value);
        Assert.True(key.IsKnown);
    }

    [Fact]
    public void MapsLettersByPhysicalPositionInsteadOfVirtualKey()
    {
        Assert.True(WindowsScanCodeMapper.TryMapHookEvent(
            scanCode: 0x10,
            isExtended: false,
            virtualKey: 0x41, // A on a hypothetical non-QWERTY layout
            out var prefix,
            out var key));

        Assert.Equal(WindowsScanCodePrefix.Base, prefix);
        Assert.Equal(PhysicalKeys.KeyQ, key.Id);
    }

    [Theory]
    [InlineData(WindowsScanCodeMapper.VirtualKeyPause)]
    [InlineData(WindowsScanCodeMapper.VirtualKeyCancel)]
    public void InfersPauseE1FromVirtualKey(uint virtualKey)
    {
        Assert.True(WindowsScanCodeMapper.TryMapHookEvent(
            0x45,
            isExtended: false,
            virtualKey,
            out var prefix,
            out var key));

        Assert.Equal(WindowsScanCodePrefix.E1, prefix);
        Assert.Equal(PhysicalKeys.Pause, key.Id);
    }

    [Fact]
    public void KeepsNumLockDistinctFromPause()
    {
        Assert.True(WindowsScanCodeMapper.TryMapHookEvent(
            0x45,
            isExtended: false,
            virtualKey: 0x90,
            out var prefix,
            out var key));

        Assert.Equal(WindowsScanCodePrefix.Base, prefix);
        Assert.Equal(PhysicalKeys.NumLock, key.Id);
    }

    [Theory]
    [InlineData(0u, 0x41u)]
    [InlineData(0x1Eu, WindowsScanCodeMapper.VirtualKeyPacket)]
    public void RejectsEventsWithoutAPhysicalIdentity(uint scanCode, uint virtualKey)
    {
        Assert.False(WindowsScanCodeMapper.TryMapHookEvent(
            scanCode,
            isExtended: false,
            virtualKey,
            out _,
            out _));
    }

    [Theory]
    [InlineData(0x0060, WindowsScanCodePrefix.Base, "win.scan.base.0060")]
    [InlineData(0x0060, WindowsScanCodePrefix.E0, "win.scan.e0.0060")]
    [InlineData(0x1234, WindowsScanCodePrefix.Base, "win.scan.base.1234")]
    public void UnknownScansHaveDeterministicStatsOnlyIdentity(
        ushort scanCode,
        WindowsScanCodePrefix prefix,
        string expectedId)
    {
        Assert.True(WindowsScanCodeMapper.TryMap(scanCode, prefix, out var key));

        Assert.Equal(expectedId, key.Id.Value);
        Assert.Equal(KeyboardRowId.R4, key.Row);
        Assert.Null(key.SpecialKey);
        Assert.False(key.IsKnown);
        Assert.False(key.IsDiyAssignable);
    }

    [Fact]
    public void CarriesSoundResolutionMetadataFromCoreCatalog()
    {
        Assert.True(WindowsScanCodeMapper.TryMap(0x39, WindowsScanCodePrefix.Base, out var space));
        Assert.Equal(KeyboardRowId.R4, space.Row);
        Assert.Equal(KeyboardSpecialKeyId.Space, space.SpecialKey);

        Assert.True(WindowsScanCodeMapper.TryMap(0x10, WindowsScanCodePrefix.Base, out var q));
        Assert.Equal(KeyboardRowId.R1, q.Row);
        Assert.Null(q.SpecialKey);
    }
}
