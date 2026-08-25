using Battuta.Windows.Lifecycle;

namespace Battuta.Windows.Tests.Platform.Lifecycle;

public sealed class ExitCoordinatorTests
{
    [Fact]
    public async Task CancelledParticipantPreventsServiceShutdown()
    {
        var first = new RecordingParticipant("first", ExitPreparationResult.Ready);
        var editor = new RecordingParticipant("editor", ExitPreparationResult.Cancel);
        using var coordinator = new ExitCoordinator([first, editor]);

        var result = await coordinator.RequestExitAsync(ExitReason.UserRequested);

        Assert.Equal(ExitOutcome.Cancelled, result);
        Assert.Equal(["first:prepare", "editor:prepare"], first.Events.Concat(editor.Events));
    }

    [Fact]
    public async Task ReadyParticipantsStopInReverseOrder()
    {
        var events = new List<string>();
        var first = new RecordingParticipant("first", ExitPreparationResult.Ready, events);
        var second = new RecordingParticipant("second", ExitPreparationResult.Ready, events);
        using var coordinator = new ExitCoordinator([first, second]);

        var result = await coordinator.RequestExitAsync(ExitReason.UserRequested);

        Assert.Equal(ExitOutcome.Completed, result);
        Assert.Equal(
            ["first:prepare", "second:prepare", "second:stop", "first:stop"],
            events);
    }

    private sealed class RecordingParticipant : IExitParticipant
    {
        private readonly string _name;
        private readonly ExitPreparationResult _result;

        public RecordingParticipant(
            string name,
            ExitPreparationResult result,
            List<string>? sharedEvents = null)
        {
            _name = name;
            _result = result;
            Events = sharedEvents ?? [];
        }

        public List<string> Events { get; }

        public Task<ExitPreparationResult> PrepareToExitAsync(
            ExitReason reason,
            CancellationToken cancellationToken)
        {
            Events.Add($"{_name}:prepare");
            return Task.FromResult(_result);
        }

        public Task StopAsync(ExitReason reason, CancellationToken cancellationToken)
        {
            Events.Add($"{_name}:stop");
            return Task.CompletedTask;
        }
    }
}
