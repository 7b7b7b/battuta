using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace Battuta.Windows.Audio;

public sealed class AudioOutputSessionStoppedEventArgs(Exception? exception) : EventArgs
{
    public Exception? Exception { get; } = exception;
}

/// <summary>A small seam around the hardware-bound NAudio player for deterministic recovery tests.</summary>
public interface IAudioOutputSession : IAsyncDisposable
{
    event EventHandler<AudioOutputSessionStoppedEventArgs>? Stopped;

    bool IsPlaying { get; }
}

public interface IAudioOutputSessionFactory
{
    ValueTask<IAudioOutputSession> CreateAndStartAsync(
        ISampleProvider source,
        CancellationToken cancellationToken);
}

/// <summary>
/// Creates one routed shared-mode WASAPI stream. Windows follows changes to the default render
/// endpoint; <see cref="AudioOutputService"/> rebuilds only after an actual stop or system resume.
/// </summary>
public sealed class WasapiOutputSessionFactory(int requestedLatencyMilliseconds = 25)
    : IAudioOutputSessionFactory
{
    public int RequestedLatencyMilliseconds { get; } =
        requestedLatencyMilliseconds > 0
            ? requestedLatencyMilliseconds
            : throw new ArgumentOutOfRangeException(nameof(requestedLatencyMilliseconds));

    public async ValueTask<IAudioOutputSession> CreateAndStartAsync(
        ISampleProvider source,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(source);
        cancellationToken.ThrowIfCancellationRequested();

        var player = await new WasapiPlayerBuilder()
            .WithDefaultDeviceStreamRouting()
            .WithSharedMode()
            .WithEventSync()
            .WithLatency(RequestedLatencyMilliseconds)
            .WithMmcssThreadPriority("Pro Audio")
            .WithCategory(AudioStreamCategory.SoundEffects)
            .BuildAsync()
            .ConfigureAwait(false);

        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            player.Init(source);
            player.Play();
            return new WasapiOutputSession(player);
        }
        catch
        {
            await player.DisposeAsync().ConfigureAwait(false);
            throw;
        }
    }
}

public sealed class WasapiOutputSession : IAudioOutputSession
{
    private readonly WasapiPlayer player;
    private int disposed;

    internal WasapiOutputSession(WasapiPlayer player)
    {
        this.player = player ?? throw new ArgumentNullException(nameof(player));
        player.PlaybackStopped += HandlePlaybackStopped;
    }

    public event EventHandler<AudioOutputSessionStoppedEventArgs>? Stopped;

    public bool IsPlaying =>
        Volatile.Read(ref disposed) == 0 && player.PlaybackState == PlaybackState.Playing;

    public int ActualLatencyMilliseconds => player.LatencyMilliseconds;

    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0)
        {
            return;
        }

        player.PlaybackStopped -= HandlePlaybackStopped;
        await player.DisposeAsync().ConfigureAwait(false);
    }

    private void HandlePlaybackStopped(object? sender, StoppedEventArgs eventArgs)
    {
        if (Volatile.Read(ref disposed) == 0)
        {
            Stopped?.Invoke(this, new AudioOutputSessionStoppedEventArgs(eventArgs.Exception));
        }
    }
}
