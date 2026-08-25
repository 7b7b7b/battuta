using System.IO;

namespace Battuta.Windows.Settings;

/// <summary>
/// Coalesces rapid UI changes (notably slider drags) while still exposing an
/// explicit flush for orderly application shutdown.
/// </summary>
public sealed class SettingsAutosaveService : IAsyncDisposable
{
    private readonly IAppSettingsStore _store;
    private readonly TimeSpan _delay;
    private readonly object _gate = new();
    private CancellationTokenSource? _scheduledSaveCancellation;
    private Task _scheduledSaveTask = Task.CompletedTask;
    private AppSettingsSnapshot? _pending;
    private bool _disposed;

    public SettingsAutosaveService(IAppSettingsStore store, TimeSpan? delay = null)
    {
        _store = store ?? throw new ArgumentNullException(nameof(store));
        _delay = delay ?? TimeSpan.FromMilliseconds(200);
        if (_delay < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(delay));
        }
    }

    public event EventHandler<Exception>? SaveFailed;

    public void Schedule(AppSettingsSnapshot settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            _pending = settings.Normalize();
            _scheduledSaveCancellation?.Cancel();
            _scheduledSaveCancellation?.Dispose();
            _scheduledSaveCancellation = new CancellationTokenSource();
            _scheduledSaveTask = SaveAfterDelayAsync(_scheduledSaveCancellation.Token);
        }
    }

    public async Task FlushAsync(CancellationToken cancellationToken = default)
    {
        AppSettingsSnapshot? pending;
        Task scheduledSave;
        lock (_gate)
        {
            _scheduledSaveCancellation?.Cancel();
            pending = _pending;
            _pending = null;
            scheduledSave = _scheduledSaveTask;
        }

        await scheduledSave.ConfigureAwait(false);
        if (pending is not null)
        {
            await _store.SaveAsync(pending, cancellationToken).ConfigureAwait(false);
        }
    }

    public async ValueTask DisposeAsync()
    {
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
        }

        try
        {
            await FlushAsync().ConfigureAwait(false);
        }
        finally
        {
            lock (_gate)
            {
                _scheduledSaveCancellation?.Dispose();
                _scheduledSaveCancellation = null;
            }
        }
    }

    private async Task SaveAfterDelayAsync(CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(_delay, cancellationToken).ConfigureAwait(false);
            AppSettingsSnapshot? pending;
            lock (_gate)
            {
                pending = _pending;
                _pending = null;
            }

            if (pending is not null)
            {
                await _store.SaveAsync(pending, cancellationToken).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            SaveFailed?.Invoke(this, exception);
        }
    }
}
