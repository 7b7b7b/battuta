using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace Battuta.Windows.Audio;

/// <summary>Decodes bundled WAV/MP3 files outside the input and render hot paths.</summary>
public sealed class PcmSampleDecoder
{
    // Mirrors the macOS import guard. Normal sound-pack assets are far smaller (five seconds max).
    public const int MaximumDecodedPcmBytes = 64 * 1024 * 1024;
    private const int ReadBufferFrames = 4_096;
    private readonly int maximumDecodedPcmBytes;

    public PcmSampleDecoder(int maximumDecodedPcmBytes = MaximumDecodedPcmBytes)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(maximumDecodedPcmBytes, sizeof(float));
        this.maximumDecodedPcmBytes = maximumDecodedPcmBytes;
    }

    public int DecodedPcmByteLimit => maximumDecodedPcmBytes;

    public PreparedPcmSample Decode(
        string path,
        bool trimKeyboardLeadingSilence,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        cancellationToken.ThrowIfCancellationRequested();

        var fullPath = Path.GetFullPath(path);
        if (!File.Exists(fullPath))
        {
            throw new FileNotFoundException("Audio sample was not found.", fullPath);
        }

        using var reader = OpenReader(fullPath);
        if (reader.WaveFormat.SampleRate <= 0 || reader.WaveFormat.Channels <= 0)
        {
            throw new InvalidDataException($"Audio sample has an invalid format: {fullPath}");
        }

        ISampleProvider provider = reader.ToSampleProvider();
        if (provider.WaveFormat.Channels != 1)
        {
            provider = new DownmixToMonoSampleProvider(provider);
        }

        if (provider.WaveFormat.SampleRate != AudioConstants.SampleRate)
        {
            provider = new WdlResamplingSampleProvider(provider, AudioConstants.SampleRate);
        }

        var estimatedFrames = EstimateOutputFrames(reader, maximumDecodedPcmBytes);
        var output = new FloatBufferBuilder(
            estimatedFrames,
            maximumDecodedPcmBytes / sizeof(float),
            maximumDecodedPcmBytes);
        var readBuffer = new float[ReadBufferFrames];
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var read = provider.Read(readBuffer);
            if (read <= 0)
            {
                break;
            }

            output.Append(readBuffer.AsSpan(0, read));
        }

        var samples = output.ToArray();
        if (samples.Length == 0)
        {
            throw new InvalidDataException($"Audio sample decoded to zero frames: {fullPath}");
        }

        for (var index = 0; index < samples.Length; index++)
        {
            if (!float.IsFinite(samples[index]))
            {
                throw new InvalidDataException($"Audio sample contains a non-finite value: {fullPath}");
            }
        }

        if (trimKeyboardLeadingSilence)
        {
            samples = LeadingSilenceTrimmer.Trim(samples);
        }

        return new PreparedPcmSample(samples, takeOwnership: true);
    }

    public Task<PreparedPcmSample> DecodeAsync(
        string path,
        bool trimKeyboardLeadingSilence,
        CancellationToken cancellationToken = default) =>
        Task.Run(
            () => Decode(path, trimKeyboardLeadingSilence, cancellationToken),
            cancellationToken);

    private static WaveStream OpenReader(string fullPath) =>
        Path.GetExtension(fullPath).ToLowerInvariant() switch
        {
            ".wav" => new WaveFileReader(fullPath),
            ".mp3" => new MediaFoundationReader(
                fullPath,
                new MediaFoundationReader.MediaFoundationReaderSettings
                {
                    RequestFloatOutput = true,
                }),
            var extension => throw new NotSupportedException(
                $"Unsupported bundled audio extension '{extension}'. Only WAV and MP3 are accepted."),
        };

    private static int EstimateOutputFrames(WaveStream reader, int byteLimit)
    {
        if (reader.WaveFormat.BlockAlign <= 0 || reader.WaveFormat.SampleRate <= 0)
        {
            return ReadBufferFrames;
        }

        var sourceFrames = reader.Length / reader.WaveFormat.BlockAlign;
        var estimate = Math.Ceiling(
            sourceFrames * (double)AudioConstants.SampleRate / reader.WaveFormat.SampleRate);
        if (!double.IsFinite(estimate) || estimate <= 0)
        {
            return ReadBufferFrames;
        }

        return (int)Math.Min(estimate, byteLimit / sizeof(float));
    }

    private sealed class DownmixToMonoSampleProvider : ISampleProvider
    {
        private readonly ISampleProvider source;
        private float[] sourceBuffer = [];

        public DownmixToMonoSampleProvider(ISampleProvider source)
        {
            this.source = source ?? throw new ArgumentNullException(nameof(source));
            if (source.WaveFormat.Channels <= 1)
            {
                throw new ArgumentException("The downmixer requires a multi-channel source.", nameof(source));
            }

            WaveFormat = WaveFormat.CreateIeeeFloatWaveFormat(source.WaveFormat.SampleRate, 1);
        }

        public WaveFormat WaveFormat { get; }

        public int Read(Span<float> buffer)
        {
            var channels = source.WaveFormat.Channels;
            var requiredSourceSamples = checked(buffer.Length * channels);
            if (sourceBuffer.Length < requiredSourceSamples)
            {
                sourceBuffer = new float[requiredSourceSamples];
            }

            var sourceSamplesRead = source.Read(sourceBuffer.AsSpan(0, requiredSourceSamples));
            if (sourceSamplesRead % channels != 0)
            {
                throw new InvalidDataException("Decoded audio was not aligned to complete channel frames.");
            }

            var framesRead = sourceSamplesRead / channels;
            for (var frame = 0; frame < framesRead; frame++)
            {
                double sum = 0;
                var sourceOffset = frame * channels;
                for (var channel = 0; channel < channels; channel++)
                {
                    sum += sourceBuffer[sourceOffset + channel];
                }

                buffer[frame] = (float)(sum / channels);
            }

            return framesRead;
        }
    }

    private sealed class FloatBufferBuilder
    {
        private readonly int maximumCount;
        private readonly int maximumBytes;
        private float[] buffer;
        private int count;

        public FloatBufferBuilder(int initialCapacity, int maximumCount, int maximumBytes)
        {
            this.maximumCount = maximumCount;
            this.maximumBytes = maximumBytes;
            buffer = new float[Math.Clamp(initialCapacity, 1, maximumCount)];
        }

        public void Append(ReadOnlySpan<float> values)
        {
            if (values.IsEmpty)
            {
                return;
            }

            var required = checked(count + values.Length);
            if (required > maximumCount)
            {
                throw new InvalidDataException(
                    $"Decoded PCM exceeds the {maximumBytes / (1024 * 1024)} MiB safety limit.");
            }

            EnsureCapacity(required);
            values.CopyTo(buffer.AsSpan(count));
            count = required;
        }

        public float[] ToArray()
        {
            if (count == buffer.Length)
            {
                return buffer;
            }

            return buffer.AsSpan(0, count).ToArray();
        }

        private void EnsureCapacity(int required)
        {
            if (required <= buffer.Length)
            {
                return;
            }

            var next = (int)Math.Min(
                maximumCount,
                Math.Max((long)required, (long)buffer.Length * 2));
            Array.Resize(ref buffer, next);
        }
    }
}
