using System.Text;
using Battuta.Windows.Audio;

namespace Battuta.Windows.Tests.Audio;

public sealed class PcmSampleDecoderTests
{
    [Fact]
    public void Stereo44100PcmIsDownmixedAndResampledToCanonicalFormat()
    {
        var path = Path.Combine(Path.GetTempPath(), $"battuta-decoder-{Guid.NewGuid():N}.wav");
        try
        {
            WriteStereoPcm16Fixture(path, sampleRate: 44_100, frameCount: 4_410);
            var decoder = new PcmSampleDecoder();

            var decoded = decoder.Decode(path, trimKeyboardLeadingSilence: false);

            Assert.InRange(decoded.FrameCount, 4_795, 4_805);
            Assert.Equal(TimeSpan.FromMilliseconds(100).TotalSeconds, decoded.Duration.TotalSeconds, 3);
            Assert.Contains(decoded.Samples.Span.ToArray(), sample => MathF.Abs(sample) > 0.01f);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void UnsupportedExtensionIsRejectedBeforeHotPath()
    {
        var path = Path.Combine(Path.GetTempPath(), $"battuta-decoder-{Guid.NewGuid():N}.bin");
        try
        {
            File.WriteAllBytes(path, [1, 2, 3, 4]);
            var decoder = new PcmSampleDecoder();

            Assert.Throws<NotSupportedException>(() =>
            {
                _ = decoder.Decode(path, false);
            });
        }
        finally
        {
            File.Delete(path);
        }
    }

    private static void WriteStereoPcm16Fixture(string path, int sampleRate, int frameCount)
    {
        const short channelCount = 2;
        const short bitsPerSample = 16;
        var blockAlign = (short)(channelCount * bitsPerSample / 8);
        var byteRate = sampleRate * blockAlign;
        var dataLength = frameCount * blockAlign;

        using var stream = File.Create(path);
        using var writer = new BinaryWriter(stream, Encoding.ASCII, leaveOpen: false);
        writer.Write(Encoding.ASCII.GetBytes("RIFF"));
        writer.Write(36 + dataLength);
        writer.Write(Encoding.ASCII.GetBytes("WAVE"));
        writer.Write(Encoding.ASCII.GetBytes("fmt "));
        writer.Write(16);
        writer.Write((short)1);
        writer.Write(channelCount);
        writer.Write(sampleRate);
        writer.Write(byteRate);
        writer.Write(blockAlign);
        writer.Write(bitsPerSample);
        writer.Write(Encoding.ASCII.GetBytes("data"));
        writer.Write(dataLength);

        for (var frame = 0; frame < frameCount; frame++)
        {
            var sine = Math.Sin(2 * Math.PI * 440 * frame / sampleRate);
            writer.Write((short)(sine * short.MaxValue * 0.5));
            writer.Write((short)(sine * short.MaxValue * 0.25));
        }
    }
}
