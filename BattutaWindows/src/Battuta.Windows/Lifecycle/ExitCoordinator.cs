namespace Battuta.Windows.Lifecycle;

public enum ExitReason
{
    UserRequested,
    UpdateInstallation,
    SystemSessionEnding,
    FatalError,
}

public enum ExitPreparationResult
{
    Ready,
    Cancel,
}

public enum ExitOutcome
{
    Completed,
    Cancelled,
    AlreadyInProgress,
}

public interface IExitParticipant
{
    Task<ExitPreparationResult> PrepareToExitAsync(
        ExitReason reason,
        CancellationToken cancellationToken);

    Task StopAsync(ExitReason reason, CancellationToken cancellationToken);
}

/// <summary>
/// Coordinates unsaved-editor confirmation followed by deterministic service
/// shutdown. Participants are prepared in registration order and stopped in
/// reverse order.
/// </summary>
public sealed class ExitCoordinator : IDisposable
{
    private readonly IReadOnlyList<IExitParticipant> _participants;
    private readonly SemaphoreSlim _exitGate = new(1, 1);
    private bool _completed;
    private bool _disposed;

    public ExitCoordinator(IEnumerable<IExitParticipant> participants)
    {
        ArgumentNullException.ThrowIfNull(participants);
        _participants = participants.ToArray();
    }

    public async Task<ExitOutcome> RequestExitAsync(
        ExitReason reason,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (!await _exitGate.WaitAsync(0, cancellationToken).ConfigureAwait(false))
        {
            return ExitOutcome.AlreadyInProgress;
        }

        try
        {
            if (_completed)
            {
                return ExitOutcome.Completed;
            }

            foreach (var participant in _participants)
            {
                var result = await participant.PrepareToExitAsync(reason, cancellationToken)
                    .ConfigureAwait(false);
                if (result == ExitPreparationResult.Cancel)
                {
                    return ExitOutcome.Cancelled;
                }
            }

            foreach (var participant in _participants.Reverse())
            {
                await participant.StopAsync(reason, cancellationToken).ConfigureAwait(false);
            }

            _completed = true;
            return ExitOutcome.Completed;
        }
        finally
        {
            _exitGate.Release();
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _exitGate.Dispose();
    }
}
