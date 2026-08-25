using System.Buffers.Binary;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace Battuta.Windows.Diy.Audio;

internal static class Pcm16WaveFile
{
    private const ushort PcmFormatTag = 0x0001;
    private const ushort ExtensibleFormatTag = 0xfffe;
    private static readonly byte[] PcmSubFormatGuid =
    [
        0x01, 0x00, 0x00, 0x00,
        0x00, 0x00,
        0x10, 0x00,
        0x80, 0x00,
        0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71,
    ];

    public static NormalizedDiyAudioInfo ValidateNormalized(
        string path,
        DiyAudioImportLimits? limits = null)
    {
        limits ??= DiyAudioImportLimits.SoundPack;
        var file = new FileInfo(path);
        if (!file.Exists)
        {
            throw new DiyAudioException("找不到规范化音频文件。");
        }

        if ((file.Attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)
        {
            throw new DiyAudioException("规范化音频必须是普通文件。");
        }

        if (!string.Equals(file.Extension, ".wav", StringComparison.OrdinalIgnoreCase))
        {
            throw new DiyAudioException("规范化资源必须是 WAV。");
        }

        if (file.Length <= 0 || file.Length > limits.MaximumSourceBytes)
        {
            throw new DiyAudioException("规范化音频文件大小超出允许范围。");
        }

        using var stream = new FileStream(
            file.FullName,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            64 * 1_024,
            FileOptions.SequentialScan);
        var byteCount = stream.Length;
        if (byteCount <= 0 || byteCount > limits.MaximumSourceBytes)
        {
            throw new DiyAudioException("规范化音频文件大小超出允许范围。");
        }

        Span<byte> header = stackalloc byte[12];
        ReadExactly(stream, header);
        if (!header[..4].SequenceEqual("RIFF"u8) || !header[8..].SequenceEqual("WAVE"u8))
        {
            throw new DiyAudioException("音频不是有效的 RIFF/WAVE 文件。");
        }

        var riffPayloadLength = BinaryPrimitives.ReadUInt32LittleEndian(header[4..8]);
        var riffEnd = checked((long)riffPayloadLength + 8);
        if (riffEnd > stream.Length || riffEnd < 12)
        {
            throw new DiyAudioException("WAV 容器长度无效或文件已截断。");
        }

        WaveFormatInfo? format = null;
        long? dataLength = null;
        var chunkHeader = new byte[8];
        while (stream.Position <= riffEnd - 8)
        {
            ReadExactly(stream, chunkHeader);
            var chunkSize = BinaryPrimitives.ReadUInt32LittleEndian(chunkHeader.AsSpan(4));
            var payloadStart = stream.Position;
            var payloadEnd = checked(payloadStart + chunkSize);
            if (payloadEnd > riffEnd)
            {
                throw new DiyAudioException("WAV 数据块已截断。");
            }

            if (chunkHeader.AsSpan(0, 4).SequenceEqual("fmt "u8))
            {
                if (format is not null)
                {
                    throw new DiyAudioException("WAV 包含多个格式块。");
                }

                if (chunkSize < 16 || chunkSize > 4_096)
                {
                    throw new DiyAudioException("WAV 格式块长度无效。");
                }

                var bytes = new byte[checked((int)chunkSize)];
                ReadExactly(stream, bytes);
                format = ParseFormat(bytes);
            }
            else if (chunkHeader.AsSpan(0, 4).SequenceEqual("data"u8))
            {
                if (dataLength is not null)
                {
                    throw new DiyAudioException("WAV 包含多个音频数据块。");
                }

                dataLength = chunkSize;
                stream.Position = payloadEnd;
            }
            else
            {
                stream.Position = payloadEnd;
            }

            if ((chunkSize & 1) != 0)
            {
                if (stream.Position >= riffEnd)
                {
                    throw new DiyAudioException("WAV 数据块缺少对齐字节。");
                }

                stream.Position++;
            }
        }

        if (format is null || dataLength is null)
        {
            throw new DiyAudioException("WAV 缺少格式块或音频数据块。");
        }

        if (!format.IsPcm || format.SampleRate != 48_000 || format.Channels != 1 ||
            format.BitsPerSample != 16 || format.BlockAlign != 2 || format.BytesPerSecond != 96_000)
        {
            throw new DiyAudioException("音频必须为 48 kHz 单声道 16-bit PCM WAV。");
        }

        if (dataLength <= 0 || dataLength % format.BlockAlign != 0)
        {
            throw new DiyAudioException("WAV 音频数据长度无效。");
        }

        var frameCount = dataLength.Value / format.BlockAlign;
        var duration = (double)frameCount / format.SampleRate;
        if (!double.IsFinite(duration) || duration < limits.MinimumDurationSeconds ||
            duration > limits.MaximumDurationSeconds)
        {
            throw new DiyAudioException("音频时长超出允许范围。");
        }

        return new NormalizedDiyAudioInfo(
            duration,
            byteCount,
            format.SampleRate,
            format.Channels,
            format.BitsPerSample);
    }

    public static string Sha256(string path, long maximumBytes = long.MaxValue)
    {
        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            64 * 1_024,
            FileOptions.SequentialScan);
        if (stream.Length <= 0 || stream.Length > maximumBytes)
        {
            throw new DiyAudioException("音频文件大小超出哈希安全限制。");
        }
        return Convert.ToHexStringLower(SHA256.HashData(stream));
    }

    public static void Write(string path, ReadOnlySpan<float> samples, int sampleRate = 48_000)
    {
        if (samples.IsEmpty)
        {
            throw new DiyAudioException("不能写入空音频。");
        }

        var parent = Path.GetDirectoryName(Path.GetFullPath(path));
        if (!string.IsNullOrEmpty(parent))
        {
            Directory.CreateDirectory(parent);
        }

        var dataSize = checked(samples.Length * sizeof(short));
        using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        using var writer = new BinaryWriter(stream, Encoding.ASCII, leaveOpen: true);
        writer.Write("RIFF"u8);
        writer.Write(checked(36 + dataSize));
        writer.Write("WAVE"u8);
        writer.Write("fmt "u8);
        writer.Write(16);
        writer.Write(PcmFormatTag);
        writer.Write((ushort)1);
        writer.Write(sampleRate);
        writer.Write(checked(sampleRate * sizeof(short)));
        writer.Write((ushort)sizeof(short));
        writer.Write((ushort)16);
        writer.Write("data"u8);
        writer.Write(dataSize);
        foreach (var value in samples)
        {
            if (!float.IsFinite(value))
            {
                throw new DiyAudioException("音频包含非有限采样值。");
            }

            var clamped = Math.Clamp(value, -1f, 0.999_969_5f);
            var quantized = (short)MathF.Round(
                clamped * short.MaxValue,
                MidpointRounding.AwayFromZero);
            writer.Write(quantized);
        }
    }

    private static WaveFormatInfo ParseFormat(ReadOnlySpan<byte> bytes)
    {
        var formatTag = BinaryPrimitives.ReadUInt16LittleEndian(bytes);
        var channels = BinaryPrimitives.ReadUInt16LittleEndian(bytes[2..]);
        var sampleRate = checked((int)BinaryPrimitives.ReadUInt32LittleEndian(bytes[4..]));
        var bytesPerSecond = checked((int)BinaryPrimitives.ReadUInt32LittleEndian(bytes[8..]));
        var blockAlign = BinaryPrimitives.ReadUInt16LittleEndian(bytes[12..]);
        var bitsPerSample = BinaryPrimitives.ReadUInt16LittleEndian(bytes[14..]);
        var isPcm = formatTag == PcmFormatTag;

        if (formatTag == ExtensibleFormatTag)
        {
            if (bytes.Length < 40 || BinaryPrimitives.ReadUInt16LittleEndian(bytes[16..]) < 22)
            {
                throw new DiyAudioException("WAVE_FORMAT_EXTENSIBLE 格式块无效。");
            }

            isPcm = bytes.Slice(24, 16).SequenceEqual(PcmSubFormatGuid);
        }

        return new WaveFormatInfo(
            isPcm,
            channels,
            sampleRate,
            bytesPerSecond,
            blockAlign,
            bitsPerSample);
    }

    private static void ReadExactly(Stream stream, Span<byte> destination)
    {
        try
        {
            stream.ReadExactly(destination);
        }
        catch (EndOfStreamException error)
        {
            throw new DiyAudioException("音频文件已截断。", error);
        }
    }

    private sealed record WaveFormatInfo(
        bool IsPcm,
        int Channels,
        int SampleRate,
        int BytesPerSecond,
        int BlockAlign,
        int BitsPerSample);
}
