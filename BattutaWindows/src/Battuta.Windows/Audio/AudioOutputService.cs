namespace Battuta.Windows.Audio;

public enum AudioOutputState
{
    Stopped,
    Starting,
    Running,
    Recovering,
    Stopping,
}

public interface IAudioRecoveryDelay
{
    ValueTask DelayAsync(TimeSpan delay, CancellationToken cancellationToken);
}

public sealed class SystemAudioRecoveryDelay : IAudioRecoveryDelay
{
    public ValueTask DelayAsync(TimeSpan delay, CancellationToken cancellationToken) =>
        new(Task.Delay(delay, cancellationToken));
}

/// <summary>
/// Owns the application's sole WASAPI session and serializes teardown/rebuild after device loss.
/// It never decodes audio and preserves loaded PCM banks across output recovery.
/// </summary>
public sealed class AudioOutputService : IAsyncDisposable
{
    private static readonly TimeSpan[] RetrySchedule =
    [
        TimeSpan.FromMilliseconds(250),
        TimeSpan.FromMilliseconds(500),
        TimeSpan.FromSeconds(1),
        TimeSpan.FromSeconds(2),
        TimeSpan.FromSeconds(4),
        TimeSpan.FromSeconds(8),
    ];

    private readonly PolyphonicSampleProvider mixer;
    private readonly IAudioOutputSessionFactory sessionFactory;
    private readonly IAudioRecoveryDelay recoveryDelay;
    private readonly CancellationTokenSource lifetimeCancellation = new();
    private readonly SemaphoreSlim lifecycleGate = new(1, 1);
    private readonly object recoveryWorkerLock = new();
    private IAudioOutputSession? session;
    private Task recoveryWorker = Task.CompletedTask;
    private int recoveryWorkerRunning;
    private int restartRequested;
    private int started;
    private int stopping;
    private int state = (int)AudioOutputState.Stopped;
    private Exception? lastError;

    public AudioOutputService(
        PolyphonicSampleProvider mixer,
        IAudioOutputSessionFactory? sessionFactory = null,
        IAudioRecoveryDelay? recoveryDelay = null)
    {
        this.mixer = mixer ?? throw new ArgumentNullException(nameof(mixer));
        this.sessionFactory = sessionFactory ?? new WasapiOutputSessionFactory();
        this.recoveryDelay = recoveryDelay ?? new SystemAudioRecoveryDelay();
    }

    public event EventHandler? StateChanged;

    public AudioOutputState State => (AudioOutputState)Volatile.Read(ref state);

    public bool IsRunning => State == AudioOutputState.Running &&
        Volatile.Read(ref session)?.IsPlaying == true;

    public Exception? LastError => Volatile.Read(ref lastError);

    /// <summary>Attempts the first start once; a failure enters bounded background recovery.</summary>
    public async Task<bool> StartAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref stopping) != 0, this);
        if (Interlocked.CompareExchange(ref started, 1, 0) != 0)
        {
            return IsRunning;
        }

        try
        {
            var startedSuccessfully = await RestartCoreAsync(cancellationToken).ConfigureAwait(false);
            if (!startedSuccessfully)
            {
                RequestRecovery();
            }

            return startedSuccessfully;
        }
        catch
        {
            if (Volatile.Read(ref stopping) == 0)
            {
                Interlocked.CompareExchange(ref started, 0, 1);
            }

            throw;
        }
    }

    public Task WarmUpAsync(
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default) =>
        mixer.WaitForFirstRenderAsync(timeout ?? TimeSpan.FromSeconds(1), cancellationToken);

    /// <summary>Used for a real playback stop, a resume notification, or a failed health check.</summary>
    public void RequestRecovery()
    {
        if (Volatile.Read(ref started) == 0 || Volatile.Read(ref stopping) != 0)
        {
            return;
        }

        Interlocked.Exchange(ref restartRequested, 1);
        EnsureRecoveryWorker();
    }

    /// <summary>
    /// Default-device routing normally handles endpoint changes itself. Endpoint notifications only
    /// accelerate retry while already recovering and therefore do not disrupt a healthy routed stream.
    /// </summary>
    public void NotifyDeviceAvailabilityChanged()
    {
        if (State == AudioOutputState.Recovering)
        {
            RequestRecovery();
        }
    }

    public void NotifySystemResumed() => RequestRecovery();

    public void CheckHealth()
    {
        if (State == AudioOutputState.Running && Volatile.Read(ref session)?.IsPlaying != true)
        {
            RequestRecovery();
        }
    }

    public async Task StopAsync()
    {
        if (Interlocked.Exchange(ref stopping, 1) != 0)
        {
            return;
        }

        SetState(AudioOutputState.Stopping);
        lifetimeCancellation.Cancel();

        Task worker;
        lock (recoveryWorkerLock)
        {
            worker = recoveryWorker;
        }

        try
        {
            await worker.ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (lifetimeCancellation.IsCancellationRequested)
        {
        }

        await lifecycleGate.WaitAsync().ConfigureAwait(false);
        try
        {
            await DisposeCurrentSessionAsync().ConfigureAwait(false);
            mixer.SuspendForOutputRestart();
            SetState(AudioOutputState.Stopped);
        }
        finally
        {
            lifecycleGate.Release();
        }
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync().ConfigureAwait(false);
        lifetimeCancellation.Dispose();
        lifecycleGate.Dispose();
    }

    private void EnsureRecoveryWorker()
    {
        lock (recoveryWorkerLock)
        {
            if (recoveryWorkerRunning != 0 || Volatile.Read(ref stopping) != 0)
            {
                return;
            }

            recoveryWorkerRunning = 1;
            recoveryWorker = Task.Run(RecoveryWorkerAsync);
        }
    }

    private async Task RecoveryWorkerAsync()
    {
        var retryIndex = 0;
        try
        {
            while (!lifetimeCancellation.IsCancellationRequested)
            {
                Interlocked.Exchange(ref restartRequested, 0);
                var success = await RestartCoreAsync(lifetimeCancellation.Token).ConfigureAwait(false);
                if (success)
                {
                    retryIndex = 0;
                    if (Volatile.Read(ref restartRequested) == 0)
                    {
                        return;
                    }

                    continue;
                }

                var delay = RetrySchedule[Math.Min(retryIndex, RetrySchedule.Length - 1)];
                retryIndex++;
                await recoveryDelay.DelayAsync(delay, lifetimeCancellation.Token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (lifetimeCancellation.IsCancellationRequested)
        {
        }
        finally
        {
            var reschedule = false;
            lock (recoveryWorkerLock)
            {
                recoveryWorkerRunning = 0;
                reschedule = Volatile.Read(ref restartRequested) != 0
                    && Volatile.Read(ref stopping) == 0;
            }

            if (reschedule)
            {
                EnsureRecoveryWorker();
            }
        }
    }

    private async Task<bool> RestartCoreAsync(CancellationToken cancellationToken)
    {
        using var linkedCancellation = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            lifetimeCancellation.Token);
        var token = linkedCancellation.Token;
        await lifecycleGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            if (Volatile.Read(ref stopping) != 0)
            {
                return false;
            }

            SetState(AudioOutputState.Starting);
            await DisposeCurrentSessionAsync().ConfigureAwait(false);
            mixer.SuspendForOutputRestart();

            IAudioOutputSession? uncommittedSession = null;
            try
            {
                uncommittedSession = await sessionFactory
                    .CreateAndStartAsync(mixer, token)
                    .ConfigureAwait(false);
                token.ThrowIfCancellationRequested();
                uncommittedSession.Stopped += HandleSessionStopped;
                Volatile.Write(ref session, uncommittedSession);
                uncommittedSession = null;
                mixer.ResumeAfterOutputRestart();
                Volatile.Write(ref lastError, null);
                SetState(AudioOutputState.Running);
                return true;
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception error)
            {
                Volatile.Write(ref lastError, error);
                SetState(AudioOutputState.Recovering);
                return false;
            }
            finally
            {
                if (uncommittedSession is not null)
                {
                    await uncommittedSession.DisposeAsync().ConfigureAwait(false);
                }
            }
        }
        finally
        {
            lifecycleGate.Release();
        }
    }

    private async ValueTask DisposeCurrentSessionAsync()
    {
        var current = Interlocked.Exchange(ref session, null);
        if (current is null)
        {
            return;
        }

        current.Stopped -= HandleSessionStopped;
        try
        {
            await current.DisposeAsync().ConfigureAwait(false);
        }
        catch (Exception error)
        {
            Volatile.Write(ref lastError, error);
        }
    }

    private void HandleSessionStopped(object? sender, AudioOutputSessionStoppedEventArgs eventArgs)
    {
        if (Volatile.Read(ref stopping) != 0)
        {
            return;
        }

        if (eventArgs.Exception is not null)
        {
            Volatile.Write(ref lastError, eventArgs.Exception);
        }

        RequestRecovery();
    }

    private void SetState(AudioOutputState next)
    {
        var previous = (AudioOutputState)Interlocked.Exchange(ref state, (int)next);
        if (previous != next)
        {
            StateChanged?.Invoke(this, EventArgs.Empty);
        }
    }
}
