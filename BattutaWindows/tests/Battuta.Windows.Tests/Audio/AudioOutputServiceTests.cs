using System.Collections.Concurrent;
using Battuta.Windows.Audio;
using NAudio.Wave;

namespace Battuta.Windows.Tests.Audio;

public sealed class AudioOutputServiceTests
{
    [Fact]
    public async Task StartCreatesOneContinuousSessionAndWarmsMixer()
    {
        var mixer = new PolyphonicSampleProvider();
        var factory = new FakeSessionFactory(pumpFirstRead: true);
        await using var service = new AudioOutputService(mixer, factory, new ImmediateDelay());

        var started = await service.StartAsync();
        await service.WarmUpAsync();

        Assert.True(started);
        Assert.True(service.IsRunning);
        Assert.Equal(AudioOutputState.Running, service.State);
        Assert.Equal(1, factory.CreateCount);
        Assert.Single(factory.Sessions);
    }

    [Fact]
    public async Task FailedFirstStartRetriesWithoutBlockingApplicationStartup()
    {
        var mixer = new PolyphonicSampleProvider();
        var factory = new FakeSessionFactory(
            pumpFirstRead: true,
            failuresBeforeSuccess: 1);
        await using var service = new AudioOutputService(mixer, factory, new ImmediateDelay());

        var firstAttempt = await service.StartAsync();
        await WaitUntilAsync(() => service.IsRunning);

        Assert.False(firstAttempt);
        Assert.Equal(2, factory.CreateCount);
        Assert.Null(service.LastError);
    }

    [Fact]
    public async Task SessionThatStopsBeforeCommitIsDisposedAndRetried()
    {
        var mixer = new PolyphonicSampleProvider();
        var factory = new FakeSessionFactory(
            pumpFirstRead: true,
            stoppedSessionsBeforeSuccess: 1);
        await using var service = new AudioOutputService(mixer, factory, new ImmediateDelay());

        Assert.False(await service.StartAsync());
        await WaitUntilAsync(() => service.IsRunning);

        Assert.Equal(2, factory.CreateCount);
        Assert.True(factory.Sessions[0].IsDisposed);
        Assert.False(factory.Sessions[1].IsDisposed);
        Assert.Null(service.LastError);
    }

    [Fact]
    public async Task PlaybackFailureDisposesOldSessionBeforeReplacement()
    {
        var log = new ConcurrentQueue<string>();
        var mixer = new PolyphonicSampleProvider();
        var factory = new FakeSessionFactory(pumpFirstRead: true, log: log);
        await using var service = new AudioOutputService(mixer, factory, new ImmediateDelay());
        Assert.True(await service.StartAsync());
        var first = factory.Sessions[0];

        first.Fail(new InvalidOperationException("device invalidated"));
        await WaitUntilAsync(() => factory.CreateCount >= 2 && service.IsRunning);

        var entries = log.ToArray();
        Assert.True(Array.IndexOf(entries, "dispose-1") < Array.IndexOf(entries, "create-2"));
        Assert.True(first.IsDisposed);
        Assert.Equal(2, factory.CreateCount);
    }

    [Fact]
    public async Task IdleOutputResumesTheSameSessionOnTheNextSound()
    {
        var mixer = new PolyphonicSampleProvider();
        var factory = new FakeSessionFactory(pumpFirstRead: true);
        await using var service = new AudioOutputService(mixer, factory, new ImmediateDelay());
        Assert.True(await service.StartAsync());
        var first = factory.Sessions[0];

        EndMixerForIdle(mixer);
        first.CompleteNormally();
        await WaitUntilAsync(() => service.State == AudioOutputState.Idle);
        Assert.False(service.IsRunning);

        Assert.True(mixer.TrySchedule(new PreparedPcmSample([0.25f]), 1, 1));
        await WaitUntilAsync(() => service.IsRunning && first.ResumeCount == 1);

        Assert.Equal(1, factory.CreateCount);
        Assert.False(first.IsDisposed);
        Assert.Equal(0.25f, first.LastResumeFirstSample);
        Assert.Null(service.LastError);
    }

    [Fact]
    public async Task SoundQueuedDuringEndOfStreamIsPreservedForIdleWake()
    {
        var mixer = new PolyphonicSampleProvider();
        var factory = new FakeSessionFactory(pumpFirstRead: true);
        await using var service = new AudioOutputService(mixer, factory, new ImmediateDelay());
        Assert.True(await service.StartAsync());
        var first = factory.Sessions[0];

        EndMixerForIdle(mixer);
        Assert.True(mixer.TrySchedule(new PreparedPcmSample([0.4f]), 1, 1));
        first.CompleteNormally();
        await WaitUntilAsync(() => service.IsRunning && first.ResumeCount == 1);

        Assert.Equal(1, factory.CreateCount);
        Assert.Equal(0.4f, first.LastResumeFirstSample);
        Assert.Equal(0, mixer.QueuedCommandCount);
        Assert.False(mixer.IsSchedulingSuspended);
    }

    [Fact]
    public async Task StopCancelsAWaitingRecoveryLoop()
    {
        var delay = new BlockingDelay();
        var mixer = new PolyphonicSampleProvider();
        var factory = new FakeSessionFactory(
            pumpFirstRead: false,
            failuresBeforeSuccess: int.MaxValue);
        await using var service = new AudioOutputService(mixer, factory, delay);

        Assert.False(await service.StartAsync());
        await delay.Started.Task.WaitAsync(TimeSpan.FromSeconds(1));
        await service.StopAsync();

        Assert.Equal(AudioOutputState.Stopped, service.State);
        Assert.Equal(2, factory.CreateCount); // first start plus the recovery worker's immediate attempt
        Assert.True(delay.WasCancelled);
    }

    private static async Task WaitUntilAsync(Func<bool> predicate)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        while (!predicate())
        {
            await Task.Delay(10, timeout.Token);
        }
    }

    private static void EndMixerForIdle(PolyphonicSampleProvider mixer)
    {
        var output = new float[960];
        var ended = false;
        for (var index = 0; index < 101; index++)
        {
            if (mixer.Read(output) == 0)
            {
                ended = true;
                break;
            }
        }

        Assert.True(ended);
        Assert.True(mixer.OutputEndedForIdle);
    }

    private sealed class FakeSessionFactory : IAudioOutputSessionFactory
    {
        private readonly bool pumpFirstRead;
        private readonly ConcurrentQueue<string>? log;
        private int failuresRemaining;
        private int stoppedSessionsRemaining;
        private int createCount;

        public FakeSessionFactory(
            bool pumpFirstRead,
            int failuresBeforeSuccess = 0,
            int stoppedSessionsBeforeSuccess = 0,
            ConcurrentQueue<string>? log = null)
        {
            this.pumpFirstRead = pumpFirstRead;
            failuresRemaining = failuresBeforeSuccess;
            stoppedSessionsRemaining = stoppedSessionsBeforeSuccess;
            this.log = log;
        }

        public int CreateCount => Volatile.Read(ref createCount);

        public List<FakeSession> Sessions { get; } = [];

        public ValueTask<IAudioOutputSession> CreateAndStartAsync(
            ISampleProvider source,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var sequence = Interlocked.Increment(ref createCount);
            log?.Enqueue($"create-{sequence}");
            if (Interlocked.Decrement(ref failuresRemaining) >= 0)
            {
                throw new InvalidOperationException("No render device");
            }

            if (pumpFirstRead)
            {
                source.Read(new float[2]);
            }

            var session = new FakeSession(sequence, log, source);
            if (Interlocked.Decrement(ref stoppedSessionsRemaining) >= 0)
            {
                session.StopWithoutNotification();
            }

            lock (Sessions)
            {
                Sessions.Add(session);
            }

            return ValueTask.FromResult<IAudioOutputSession>(session);
        }
    }

    private sealed class FakeSession(
        int sequence,
        ConcurrentQueue<string>? log,
        ISampleProvider source) : IAudioOutputSession
    {
        private int disposed;
        private int playing = 1;
        private int resumeCount;
        private float lastResumeFirstSample;

        public event EventHandler<AudioOutputSessionStoppedEventArgs>? Stopped;

        public bool IsPlaying =>
            Volatile.Read(ref disposed) == 0 && Volatile.Read(ref playing) != 0;

        public bool IsDisposed => Volatile.Read(ref disposed) != 0;

        public int ResumeCount => Volatile.Read(ref resumeCount);

        public float LastResumeFirstSample => Volatile.Read(ref lastResumeFirstSample);

        public void Resume()
        {
            ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
            Interlocked.Increment(ref resumeCount);
            Volatile.Write(ref playing, 1);
            var output = new float[2];
            _ = source.Read(output);
            Volatile.Write(ref lastResumeFirstSample, output[0]);
        }

        public void CompleteNormally()
        {
            Volatile.Write(ref playing, 0);
            Stopped?.Invoke(this, new AudioOutputSessionStoppedEventArgs(exception: null));
        }

        public void StopWithoutNotification() => Volatile.Write(ref playing, 0);

        public void Fail(Exception error)
        {
            Volatile.Write(ref playing, 0);
            Stopped?.Invoke(this, new AudioOutputSessionStoppedEventArgs(error));
        }

        public ValueTask DisposeAsync()
        {
            if (Interlocked.Exchange(ref disposed, 1) == 0)
            {
                Volatile.Write(ref playing, 0);
                log?.Enqueue($"dispose-{sequence}");
            }

            return ValueTask.CompletedTask;
        }
    }

    private sealed class ImmediateDelay : IAudioRecoveryDelay
    {
        public ValueTask DelayAsync(TimeSpan delay, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return ValueTask.CompletedTask;
        }
    }

    private sealed class BlockingDelay : IAudioRecoveryDelay
    {
        public TaskCompletionSource Started { get; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        public bool WasCancelled { get; private set; }

        public async ValueTask DelayAsync(TimeSpan delay, CancellationToken cancellationToken)
        {
            Started.TrySetResult();
            try
            {
                await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                WasCancelled = true;
                throw;
            }
        }
    }
}
