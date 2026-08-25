using System.Collections.Concurrent;
using NAudio.Wave;

namespace Battuta.Windows.Audio;

/// <summary>
/// Allocation-free render provider backed by a fixed sixteen-voice pool.
/// Producers enqueue immutable start commands; only the WASAPI render thread mutates voices.
/// </summary>
public sealed class PolyphonicSampleProvider : ISampleProvider
{
    private readonly ConcurrentQueue<StartVoiceCommand> commands = new();
    private readonly VoiceState[] voices;
    private readonly TaskCompletionSource renderStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private int queuedCommandCount;
    private int voiceCursor;
    private int resetRequested;
    private int schedulingSuspended;
    private int generation;
    private int activeVoiceCount;
    private long droppedCommandCount;
    private long voiceStealCount;

    public PolyphonicSampleProvider(int voiceCount = AudioConstants.VoiceCount)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(voiceCount);

        voices = new VoiceState[voiceCount];
        WaveFormat = WaveFormat.CreateIeeeFloatWaveFormat(
            AudioConstants.SampleRate,
            AudioConstants.OutputChannelCount);
    }

    public WaveFormat WaveFormat { get; }

    public int VoiceCount => voices.Length;

    public int ActiveVoiceCount => Volatile.Read(ref activeVoiceCount);

    public int QueuedCommandCount => Math.Max(0, Volatile.Read(ref queuedCommandCount));

    public long DroppedCommandCount => Interlocked.Read(ref droppedCommandCount);

    public long VoiceStealCount => Interlocked.Read(ref voiceStealCount);

    public bool IsSchedulingSuspended => Volatile.Read(ref schedulingSuspended) != 0;

    public bool TrySchedule(PreparedPcmSample sample, float gain, float rate)
    {
        ArgumentNullException.ThrowIfNull(sample);

        if (Volatile.Read(ref schedulingSuspended) != 0)
        {
            return false;
        }

        if (!float.IsFinite(gain) || !float.IsFinite(rate))
        {
            return false;
        }

        gain = Math.Clamp(gain, 0f, 1f);
        rate = Math.Clamp(
            rate,
            AudioConstants.MinimumPlaybackRate,
            AudioConstants.MaximumPlaybackRate);

        var nextCount = Interlocked.Increment(ref queuedCommandCount);
        if (nextCount > AudioConstants.MaximumQueuedCommands)
        {
            Interlocked.Decrement(ref queuedCommandCount);
            Interlocked.Increment(ref droppedCommandCount);
            return false;
        }

        commands.Enqueue(new StartVoiceCommand(
            sample,
            gain,
            rate,
            Volatile.Read(ref generation)));
        return true;
    }

    /// <summary>
    /// Invalidates queued clicks and asks the next render callback to clear active voices. This is
    /// safe to call while an output session is being torn down and prevents stale clicks on resume.
    /// </summary>
    public void ResetForOutputRestart()
    {
        Interlocked.Increment(ref generation);
        Volatile.Write(ref resetRequested, 1);
    }

    public void SuspendForOutputRestart()
    {
        Volatile.Write(ref schedulingSuspended, 1);
        ResetForOutputRestart();
    }

    public void ResumeAfterOutputRestart()
    {
        ResetForOutputRestart();
        Volatile.Write(ref schedulingSuspended, 0);
    }

    public Task WaitForFirstRenderAsync(TimeSpan timeout, CancellationToken cancellationToken = default)
    {
        if (timeout <= TimeSpan.Zero && timeout != Timeout.InfiniteTimeSpan)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }

        return timeout == Timeout.InfiniteTimeSpan
            ? renderStarted.Task.WaitAsync(cancellationToken)
            : renderStarted.Task.WaitAsync(timeout, cancellationToken);
    }

    public int Read(Span<float> buffer)
    {
        buffer.Clear();
        renderStarted.TrySetResult();

        if (Interlocked.Exchange(ref resetRequested, 0) != 0)
        {
            Array.Clear(voices);
            voiceCursor = 0;
        }

        DrainCommands();

        var outputFrames = buffer.Length / AudioConstants.OutputChannelCount;
        for (var voiceIndex = 0; voiceIndex < voices.Length; voiceIndex++)
        {
            ref var voice = ref voices[voiceIndex];
            if (!voice.Active || voice.Sample is null)
            {
                continue;
            }

            var samples = voice.Sample.SampleSpan;
            var position = voice.Position;
            var outputFrame = 0;
            while (outputFrame < outputFrames && position < samples.Length)
            {
                var value = CubicInterpolate(samples, position) * voice.Gain;
                var outputIndex = outputFrame * AudioConstants.OutputChannelCount;
                buffer[outputIndex] += value;
                buffer[outputIndex + 1] += value;
                position += voice.Rate;
                outputFrame++;
            }

            voice.Position = position;
            if (position >= samples.Length)
            {
                voice = default;
            }
        }

        var active = 0;
        for (var voiceIndex = 0; voiceIndex < voices.Length; voiceIndex++)
        {
            if (voices[voiceIndex].Active)
            {
                active++;
            }
        }

        Volatile.Write(ref activeVoiceCount, active);

        for (var index = 0; index < buffer.Length; index++)
        {
            buffer[index] = Math.Clamp(buffer[index], -1f, 1f);
        }

        // A full read, including silence, keeps the one WASAPI stream alive indefinitely.
        return buffer.Length;
    }

    private void DrainCommands()
    {
        var currentGeneration = Volatile.Read(ref generation);
        var drained = 0;
        while (drained < AudioConstants.MaximumQueuedCommands && commands.TryDequeue(out var command))
        {
            Interlocked.Decrement(ref queuedCommandCount);
            drained++;
            if (command.Generation != currentGeneration)
            {
                continue;
            }

            ref var voice = ref voices[voiceCursor];
            if (voice.Active)
            {
                Interlocked.Increment(ref voiceStealCount);
            }

            voice = new VoiceState(command.Sample, command.Gain, command.Rate);
            voiceCursor = (voiceCursor + 1) % voices.Length;
        }
    }

    private static float CubicInterpolate(ReadOnlySpan<float> samples, double position)
    {
        var index1 = (int)position;
        if (index1 >= samples.Length - 1)
        {
            return samples[^1];
        }

        var index0 = Math.Max(0, index1 - 1);
        var index2 = index1 + 1;
        var index3 = Math.Min(samples.Length - 1, index1 + 2);
        var fraction = (float)(position - index1);

        var p0 = samples[index0];
        var p1 = samples[index1];
        var p2 = samples[index2];
        var p3 = samples[index3];
        var fractionSquared = fraction * fraction;
        var fractionCubed = fractionSquared * fraction;

        return 0.5f * ((2f * p1)
            + ((-p0 + p2) * fraction)
            + ((2f * p0 - 5f * p1 + 4f * p2 - p3) * fractionSquared)
            + ((-p0 + 3f * p1 - 3f * p2 + p3) * fractionCubed));
    }

    private readonly record struct StartVoiceCommand(
        PreparedPcmSample Sample,
        float Gain,
        float Rate,
        int Generation);

    private struct VoiceState
    {
        public VoiceState(PreparedPcmSample sample, float gain, float rate)
        {
            Sample = sample;
            Gain = gain;
            Rate = rate;
            Position = 0;
            Active = true;
        }

        public PreparedPcmSample? Sample;
        public double Position;
        public float Gain;
        public float Rate;
        public bool Active;
    }
}
