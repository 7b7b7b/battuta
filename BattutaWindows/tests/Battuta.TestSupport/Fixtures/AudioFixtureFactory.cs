using System.Text;

namespace Battuta.TestSupport.Fixtures;

public sealed record Pcm16WaveFixture(
    string FilePath,
    int SampleRate,
    int ChannelCount,
    int FrameCount)
{
    public TimeSpan Duration => TimeSpan.FromSeconds((double)FrameCount / SampleRate);

    public int DataByteCount => checked(FrameCount * ChannelCount * sizeof(short));
}

/// <summary>Creates small deterministic PCM fixtures without depending on an audio package.</summary>
public static class AudioFixtureFactory
{
    private const int BitsPerSample = 16;
    private static readonly byte[] Riff = Encoding.ASCII.GetBytes("RIFF");
    private static readonly byte[] Wave = Encoding.ASCII.GetBytes("WAVE");
    private static readonly byte[] Format = Encoding.ASCII.GetBytes("fmt ");
    private static readonly byte[] Data = Encoding.ASCII.GetBytes("data");

    public static Pcm16WaveFixture WritePcm16Wave(
        string filePath,
        int sampleRate,
        int channelCount,
        TimeSpan duration,
        Func<int, int, double> sampleProvider)
    {
        ArgumentNullException.ThrowIfNull(sampleProvider);
        ValidateFormat(sampleRate, channelCount, duration);

        var exactFrameCount = duration.TotalSeconds * sampleRate;
        if (!double.IsFinite(exactFrameCount) || exactFrameCount > int.MaxValue)
        {
            throw new ArgumentOutOfRangeException(nameof(duration), duration, "The fixture is too large.");
        }

        var frameCount = checked((int)Math.Round(exactFrameCount, MidpointRounding.AwayFromZero));
        if (frameCount == 0)
        {
            throw new ArgumentOutOfRangeException(nameof(duration), duration, "The fixture must contain a sample.");
        }

        return WritePcm16Wave(filePath, sampleRate, channelCount, frameCount, sampleProvider);
    }

    public static Pcm16WaveFixture WritePcm16Wave(
        string filePath,
        int sampleRate,
        int channelCount,
        int frameCount,
        Func<int, int, double> sampleProvider)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        ArgumentNullException.ThrowIfNull(sampleProvider);
        ValidateFormat(sampleRate, channelCount, frameCount);

        var blockAlign = checked(channelCount * (BitsPerSample / 8));
        var byteRate = checked(sampleRate * blockAlign);
        var dataByteCount = checked(frameCount * blockAlign);
        var riffPayloadSize = checked(36 + dataByteCount);

        var parent = System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(filePath));
        if (!string.IsNullOrEmpty(parent))
        {
            Directory.CreateDirectory(parent);
        }

        using var stream = new FileStream(filePath, FileMode.Create, FileAccess.Write, FileShare.None);
        using var writer = new BinaryWriter(stream, Encoding.ASCII, leaveOpen: false);
        writer.Write(Riff);
        writer.Write(riffPayloadSize);
        writer.Write(Wave);
        writer.Write(Format);
        writer.Write(16);
        writer.Write((ushort)1);
        writer.Write(checked((ushort)channelCount));
        writer.Write(sampleRate);
        writer.Write(byteRate);
        writer.Write(checked((ushort)blockAlign));
        writer.Write((ushort)BitsPerSample);
        writer.Write(Data);
        writer.Write(dataByteCount);

        for (var frame = 0; frame < frameCount; frame++)
        {
            for (var channel = 0; channel < channelCount; channel++)
            {
                writer.Write(ToPcm16(sampleProvider(frame, channel)));
            }
        }

        return new Pcm16WaveFixture(
            System.IO.Path.GetFullPath(filePath),
            sampleRate,
            channelCount,
            frameCount);
    }

    public static Pcm16WaveFixture WriteSineWave(
        string filePath,
        TimeSpan duration,
        int sampleRate = 48_000,
        int channelCount = 1,
        double frequencyHz = 440,
        double amplitude = 0.5,
        TimeSpan leadingSilence = default)
    {
        if (!double.IsFinite(frequencyHz) || frequencyHz <= 0 || frequencyHz >= sampleRate / 2.0)
        {
            throw new ArgumentOutOfRangeException(nameof(frequencyHz));
        }

        ValidateAmplitude(amplitude);
        if (leadingSilence < TimeSpan.Zero || leadingSilence >= duration)
        {
            throw new ArgumentOutOfRangeException(nameof(leadingSilence));
        }

        var silentFrames = checked((int)Math.Round(
            leadingSilence.TotalSeconds * sampleRate,
            MidpointRounding.AwayFromZero));

        return WritePcm16Wave(
            filePath,
            sampleRate,
            channelCount,
            duration,
            (frame, _) => frame < silentFrames
                ? 0
                : amplitude * Math.Sin(2 * Math.PI * frequencyHz * (frame - silentFrames) / sampleRate));
    }

    /// <summary>
    /// Creates a stereo recording with separated press and release transients,
    /// suitable for normalization and automatic split tests.
    /// </summary>
    public static Pcm16WaveFixture WriteCompleteKeystroke(
        string filePath,
        int sampleRate = 44_100,
        TimeSpan? duration = null)
    {
        var actualDuration = duration ?? TimeSpan.FromMilliseconds(160);
        if (actualDuration < TimeSpan.FromMilliseconds(130))
        {
            throw new ArgumentOutOfRangeException(
                nameof(duration),
                actualDuration,
                "A complete-keystroke fixture needs room for two separated transients.");
        }

        return WritePcm16Wave(
            filePath,
            sampleRate,
            channelCount: 2,
            actualDuration,
            (frame, channel) =>
            {
                var time = (double)frame / sampleRate;
                var channelScale = channel == 0 ? 1.0 : 0.86;
                var press = DecayingTransient(time, start: 0.012, frequencyHz: 1_700, decaySeconds: 0.012);
                var release = DecayingTransient(time, start: 0.105, frequencyHz: 1_050, decaySeconds: 0.016);
                return channelScale * ((0.72 * press) + (0.55 * release));
            });
    }

    public static string WriteInvalidAudio(string filePath, int byteCount = 128)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(byteCount);

        var bytes = new byte[byteCount];
        for (var index = 0; index < bytes.Length; index++)
        {
            bytes[index] = (byte)((index * 31 + 17) & 0xff);
        }

        var parent = System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(filePath));
        if (!string.IsNullOrEmpty(parent))
        {
            Directory.CreateDirectory(parent);
        }

        File.WriteAllBytes(filePath, bytes);
        return System.IO.Path.GetFullPath(filePath);
    }

    private static double DecayingTransient(
        double time,
        double start,
        double frequencyHz,
        double decaySeconds)
    {
        var elapsed = time - start;
        if (elapsed < 0 || elapsed > 0.05)
        {
            return 0;
        }

        return Math.Exp(-elapsed / decaySeconds) * Math.Sin(2 * Math.PI * frequencyHz * elapsed);
    }

    private static short ToPcm16(double sample)
    {
        if (!double.IsFinite(sample))
        {
            throw new InvalidOperationException("The sample provider returned a non-finite value.");
        }

        var clamped = Math.Clamp(sample, -1, 1);
        if (clamped <= -1)
        {
            return short.MinValue;
        }

        return checked((short)Math.Round(clamped * short.MaxValue, MidpointRounding.AwayFromZero));
    }

    private static void ValidateFormat(int sampleRate, int channelCount, TimeSpan duration)
    {
        if (duration <= TimeSpan.Zero || duration > TimeSpan.FromMinutes(1))
        {
            throw new ArgumentOutOfRangeException(nameof(duration));
        }

        ValidateFormat(sampleRate, channelCount, frameCount: 1);
    }

    private static void ValidateFormat(int sampleRate, int channelCount, int frameCount)
    {
        if (sampleRate is < 1_000 or > 384_000)
        {
            throw new ArgumentOutOfRangeException(nameof(sampleRate));
        }

        if (channelCount is < 1 or > 32)
        {
            throw new ArgumentOutOfRangeException(nameof(channelCount));
        }

        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(frameCount);

        _ = checked(frameCount * channelCount * (BitsPerSample / 8));
    }

    private static void ValidateAmplitude(double amplitude)
    {
        if (!double.IsFinite(amplitude) || amplitude is < 0 or > 1)
        {
            throw new ArgumentOutOfRangeException(nameof(amplitude));
        }
    }
}
