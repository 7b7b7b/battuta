using Battuta.Core.Input;
using Battuta.Windows.Input;
using Battuta.Windows.Stats.Models;

namespace Battuta.Windows.Stats.Services;

/// <summary>Routes normalized Windows key-down events into the statistics recorder.</summary>
public sealed class TypingStatsInputEventSink(
    TypingStatsRecorder recorder,
    Func<bool> isEnabled) : IWindowsInputEventSink
{
    private readonly TypingStatsRecorder _recorder =
        recorder ?? throw new ArgumentNullException(nameof(recorder));
    private readonly Func<bool> _isEnabled =
        isEnabled ?? throw new ArgumentNullException(nameof(isEnabled));

    public ValueTask OnInputAsync(
        WindowsInputEvent inputEvent,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!_isEnabled()
            || inputEvent.Kind != WindowsInputKind.Keyboard
            || inputEvent.Keyboard.Phase != KeyPhase.Press)
        {
            return ValueTask.CompletedTask;
        }

        var foreground = inputEvent.ForegroundApplication;
        var application = new TypingApplicationIdentity(
            foreground.ProcessKey,
            foreground.DisplayName,
            foreground.ProcessName);
        var keyboard = inputEvent.Keyboard;
        _recorder.RecordKeyDown(
            keyboard.Key.Id,
            keyboard.IsRepeat,
            keyboard.IsShortcutModified,
            application,
            keyboard.Timestamp);
        return ValueTask.CompletedTask;
    }
}
