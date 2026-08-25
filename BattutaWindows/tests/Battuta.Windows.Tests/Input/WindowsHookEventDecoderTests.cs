using Battuta.Core.Input;
using Battuta.Windows.Input;

namespace Battuta.Windows.Tests.Input;

public sealed class WindowsHookEventDecoderTests
{
    [Theory]
    [InlineData(0u, WindowsInputOrigin.Hardware)]
    [InlineData(WindowsHookEventDecoder.KeyboardFlagInjected, WindowsInputOrigin.Injected)]
    [InlineData(
        WindowsHookEventDecoder.KeyboardFlagInjected
        | WindowsHookEventDecoder.KeyboardFlagLowerIntegrityInjected,
        WindowsInputOrigin.LowerIntegrityInjected)]
    public void AcceptsMappedInjectedEventsAndRetainsOrigin(
        uint flags,
        WindowsInputOrigin expectedOrigin)
    {
        var tracker = new WindowsKeyboardRepeatTracker();

        Assert.True(WindowsHookEventDecoder.TryDecodeKeyboard(
            WindowsHookEventDecoder.KeyDownMessage,
            virtualKey: 0x41,
            scanCode: 0x1E,
            flags,
            extraInfo: 0,
            nativeTimestamp: 10,
            monotonicTimestamp: 20,
            sequence: 1,
            selfInjectionSentinel: Win32InputHookService.SyntheticInputSentinel,
            tracker,
            out var input));

        Assert.Equal(PhysicalKeys.KeyA, input.Key.Id);
        Assert.Equal(expectedOrigin, input.Origin);
    }

    [Fact]
    public void IgnoresBattutaSyntheticSentinel()
    {
        Assert.False(WindowsHookEventDecoder.TryDecodeKeyboard(
            WindowsHookEventDecoder.KeyDownMessage,
            virtualKey: 0x41,
            scanCode: 0x1E,
            flags: WindowsHookEventDecoder.KeyboardFlagInjected,
            extraInfo: Win32InputHookService.SyntheticInputSentinel,
            nativeTimestamp: 10,
            monotonicTimestamp: 20,
            sequence: 1,
            selfInjectionSentinel: Win32InputHookService.SyntheticInputSentinel,
            new WindowsKeyboardRepeatTracker(),
            out _));
    }

    [Fact]
    public void DropsUnicodePacketBeforeItsScanValueCanBecomeAnId()
    {
        Assert.False(WindowsHookEventDecoder.TryDecodeKeyboard(
            WindowsHookEventDecoder.KeyDownMessage,
            virtualKey: WindowsScanCodeMapper.VirtualKeyPacket,
            scanCode: 0x4E2D, // Unicode 中 in KEYEVENTF_UNICODE's wScan field.
            flags: WindowsHookEventDecoder.KeyboardFlagInjected,
            extraInfo: 0,
            nativeTimestamp: 10,
            monotonicTimestamp: 20,
            sequence: 1,
            selfInjectionSentinel: Win32InputHookService.SyntheticInputSentinel,
            new WindowsKeyboardRepeatTracker(),
            out _));
    }

    [Fact]
    public void DerivesRepeatWithoutDependingOnVirtualKeyOrLayout()
    {
        var tracker = new WindowsKeyboardRepeatTracker();

        Assert.True(Decode(tracker, WindowsHookEventDecoder.KeyDownMessage, 1, out var first));
        Assert.True(Decode(tracker, WindowsHookEventDecoder.KeyDownMessage, 2, out var second));
        Assert.True(Decode(tracker, WindowsHookEventDecoder.KeyUpMessage, 3, out var released));
        Assert.True(Decode(tracker, WindowsHookEventDecoder.KeyDownMessage, 4, out var afterRelease));

        Assert.False(first.IsRepeat);
        Assert.True(second.IsRepeat);
        Assert.False(released.IsRepeat);
        Assert.False(afterRelease.IsRepeat);
    }

    [Theory]
    [InlineData(WindowsHookEventDecoder.LeftButtonDownMessage, 0u, WindowsPointerButton.Primary, KeyPhase.Press)]
    [InlineData(WindowsHookEventDecoder.RightButtonUpMessage, 0u, WindowsPointerButton.Secondary, KeyPhase.Release)]
    [InlineData(WindowsHookEventDecoder.MiddleButtonDownMessage, 0u, WindowsPointerButton.Middle, KeyPhase.Press)]
    [InlineData(WindowsHookEventDecoder.XButtonDownMessage, 1u << 16, WindowsPointerButton.X1, KeyPhase.Press)]
    [InlineData(WindowsHookEventDecoder.XButtonUpMessage, 2u << 16, WindowsPointerButton.X2, KeyPhase.Release)]
    public void DecodesOnlyPointerButtonTransitions(
        uint message,
        uint mouseData,
        WindowsPointerButton expectedButton,
        KeyPhase expectedPhase)
    {
        Assert.True(WindowsHookEventDecoder.TryDecodePointer(
            message,
            mouseData,
            flags: 0,
            extraInfo: 0,
            nativeTimestamp: 10,
            monotonicTimestamp: 20,
            sequence: 1,
            selfInjectionSentinel: Win32InputHookService.SyntheticInputSentinel,
            out var input));
        Assert.Equal(expectedButton, input.Button);
        Assert.Equal(expectedPhase, input.Phase);
    }

    private static bool Decode(
        WindowsKeyboardRepeatTracker tracker,
        uint message,
        ulong sequence,
        out RawWindowsKeyboardEvent input) =>
        WindowsHookEventDecoder.TryDecodeKeyboard(
            message,
            virtualKey: 0x41,
            scanCode: 0x1E,
            flags: 0,
            extraInfo: 0,
            nativeTimestamp: 10,
            monotonicTimestamp: 20,
            sequence,
            selfInjectionSentinel: Win32InputHookService.SyntheticInputSentinel,
            tracker,
            out input);
}
