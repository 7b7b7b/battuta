using System.IO;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace Battuta.Windows.Diy.Audio;

internal static class NAudioDecodePipeline
{
    public const int OutputSampleRate = 48_000;

    public static float[] DecodeMono48Khz(
        string sourcePath,
        long maximumSourceBytes,
        long maximumDecodedBytes,
        double minimumDurationSeconds,
        double maximumDurationSeconds,
        int minimumSampleRate,
        int maximumSampleRate,
        int maximumChannelCount,
        CancellationToken cancellationToken)
    {
        ValidateSourcePath(sourcePath, maximumSourceBytes);
        FileStream? sourceStream = null;
        AudioFileReader? reader = null;
        try
        {
            sourceStream = new FileStream(
                Path.GetFullPath(sourcePath),
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                64 * 1_024,
                FileOptions.SequentialScan);
            if (sourceStream.Length <= 0 || sourceStream.Length > maximumSourceBytes)
            {
                throw new DiyAudioException("音频文件超过安全大小限制。");
            }
            reader = new AudioFileReader(sourceStream);

            var sourceFormat = reader.WaveFormat;
            if (sourceFormat.SampleRate < minimumSampleRate ||
                sourceFormat.SampleRate > maximumSampleRate ||
                sourceFormat.Channels <= 0 ||
                sourceFormat.Channels > maximumChannelCount)
            {
                throw new DiyAudioException("源音频采样率或声道数超出安全范围。");
            }

            if (reader.Length <= 0 || reader.Length > maximumDecodedBytes)
            {
                throw new DiyAudioException("源音频解码后超过 64 MiB 安全上限。");
            }

            var reportedDuration = reader.TotalTime.TotalSeconds;
            if (!double.IsFinite(reportedDuration) ||
                reportedDuration < minimumDurationSeconds ||
                reportedDuration > maximumDurationSeconds)
            {
                throw new DiyAudioException(
                    $"源音频时长必须介于 {minimumDurationSeconds:0.###}–{maximumDurationSeconds:0.###} 秒。");
            }

            ISampleProvider provider = new BoundedSampleProvider(
                reader,
                maximumDecodedBytes,
                cancellationToken);
            if (sourceFormat.Channels != 1)
            {
                provider = new AveragingMonoSampleProvider(provider);
            }

            if (provider.WaveFormat.SampleRate != OutputSampleRate)
            {
                provider = new WdlResamplingSampleProvider(provider, OutputSampleRate);
            }

            var maximumFrames = checked((int)Math.Floor(maximumDurationSeconds * OutputSampleRate + 1e-9));
            var minimumFrames = checked((int)Math.Ceiling(minimumDurationSeconds * OutputSampleRate - 1e-9));
            var result = new List<float>(Math.Min(maximumFrames, 64 * 1_024));
            var buffer = new float[4_096];
            while (true)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var read = provider.Read(buffer);
                if (read == 0)
                {
                    break;
                }

                if (read < 0 || result.Count > maximumFrames - read)
                {
                    throw new DiyAudioException(
                        $"源音频时长必须介于 {minimumDurationSeconds:0.###}–{maximumDurationSeconds:0.###} 秒。");
                }

                for (var index = 0; index < read; index++)
                {
                    var sample = buffer[index];
                    if (!float.IsFinite(sample))
                    {
                        throw new DiyAudioException("源音频包含非有限采样值。");
                    }

                    result.Add(sample);
                }
            }

            if (result.Count < minimumFrames)
            {
                throw new DiyAudioException(
                    $"源音频时长必须介于 {minimumDurationSeconds:0.###}–{maximumDurationSeconds:0.###} 秒。");
            }

            if (!result.Any(sample => Math.Abs(sample) > 1e-7f))
            {
                throw new DiyAudioException("音频解码后没有可用采样。");
            }

            return result.ToArray();
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (DiyAudioException)
        {
            throw;
        }
        catch (Exception error) when (
            error is IOException or UnauthorizedAccessException or ArgumentException or
            InvalidOperationException or NotSupportedException or FormatException)
        {
            throw new DiyAudioException($"无法读取音频：{error.Message}", error);
        }
        finally
        {
            reader?.Dispose();
            sourceStream?.Dispose();
        }
    }

    private static void ValidateSourcePath(string sourcePath, long maximumSourceBytes)
    {
        if (string.IsNullOrWhiteSpace(sourcePath))
        {
            throw new DiyAudioException("未选择音频文件。");
        }

        var extension = Path.GetExtension(sourcePath);
        var allowedExtensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            ".wav", ".wave", ".aif", ".aiff", ".mp3", ".m4a", ".aac", ".wma", ".caf", ".audio",
        };
        if (!allowedExtensions.Contains(extension))
        {
            throw new DiyAudioException("不支持此音频文件格式。");
        }

        var file = new FileInfo(Path.GetFullPath(sourcePath));
        if (!file.Exists)
        {
            throw new DiyAudioException("找不到音频文件。");
        }

        if ((file.Attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)
        {
            throw new DiyAudioException("所选项目不是普通音频文件。");
        }

        if (file.Length <= 0)
        {
            throw new DiyAudioException("音频文件为空。");
        }

        if (file.Length > maximumSourceBytes)
        {
            throw new DiyAudioException("音频文件超过安全大小限制。");
        }
    }

    private sealed class BoundedSampleProvider : ISampleProvider
    {
        private readonly ISampleProvider _source;
        private readonly long _maximumSamples;
        private readonly CancellationToken _cancellationToken;
        private long _samplesRead;

        public BoundedSampleProvider(
            ISampleProvider source,
            long maximumDecodedBytes,
            CancellationToken cancellationToken)
        {
            _source = source;
            _maximumSamples = maximumDecodedBytes / sizeof(float);
            _cancellationToken = cancellationToken;
        }

        public WaveFormat WaveFormat => _source.WaveFormat;

        public int Read(Span<float> buffer)
        {
            _cancellationToken.ThrowIfCancellationRequested();
            var read = _source.Read(buffer);
            _samplesRead = checked(_samplesRead + read);
            if (_samplesRead > _maximumSamples)
            {
                throw new DiyAudioException("源音频解码后超过 64 MiB 安全上限。");
            }

            return read;
        }
    }

    private sealed class AveragingMonoSampleProvider : ISampleProvider
    {
        private readonly ISampleProvider _source;
        private readonly int _channels;
        private float[] _sourceBuffer = [];

        public AveragingMonoSampleProvider(ISampleProvider source)
        {
            _source = source;
            _channels = source.WaveFormat.Channels;
            if (_channels <= 1)
            {
                throw new ArgumentException("A multi-channel source is required.", nameof(source));
            }

            WaveFormat = WaveFormat.CreateIeeeFloatWaveFormat(source.WaveFormat.SampleRate, 1);
        }

        public WaveFormat WaveFormat { get; }

        public int Read(Span<float> buffer)
        {
            var requestedSourceSamples = checked(buffer.Length * _channels);
            if (_sourceBuffer.Length < requestedSourceSamples)
            {
                _sourceBuffer = new float[requestedSourceSamples];
            }

            var read = _source.Read(_sourceBuffer.AsSpan(0, requestedSourceSamples));
            if (read % _channels != 0)
            {
                throw new DiyAudioException("多声道音频包含不完整帧。");
            }

            var frames = read / _channels;
            for (var frame = 0; frame < frames; frame++)
            {
                double sum = 0;
                var sourceOffset = frame * _channels;
                for (var channel = 0; channel < _channels; channel++)
                {
                    sum += _sourceBuffer[sourceOffset + channel];
                }

                buffer[frame] = (float)(sum / _channels);
            }

            return frames;
        }
    }
}
