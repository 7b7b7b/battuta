namespace Battuta.Windows.Audio;

/// <summary>Matches Battuta's macOS onset-alignment rules for keyboard samples.</summary>
public static class LeadingSilenceTrimmer
{
    public const float SilenceThreshold = 0.0008f;
    public const double MaximumScanDurationSeconds = 0.25;
    public const double PreservedPrerollDurationSeconds = 0.00015;
    public const double MinimumTrimDurationSeconds = 0.0005;

    public static float[] Trim(float[] source, int sampleRate = AudioConstants.SampleRate)
    {
        ArgumentNullException.ThrowIfNull(source);
        var trimFrames = FindTrimFrameCount(source, sampleRate);
        return trimFrames == 0 ? source : source.AsSpan(trimFrames).ToArray();
    }

    public static float[] Trim(ReadOnlySpan<float> source, int sampleRate = AudioConstants.SampleRate)
    {
        var trimFrames = FindTrimFrameCount(source, sampleRate);
        return trimFrames == 0 ? source.ToArray() : source[trimFrames..].ToArray();
    }

    private static int FindTrimFrameCount(ReadOnlySpan<float> source, int sampleRate)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(sampleRate);

        if (source.IsEmpty)
        {
            return 0;
        }

        var scanFrameCount = Math.Min(
            source.Length,
            checked((int)Math.Ceiling(sampleRate * MaximumScanDurationSeconds)));
        var firstAudibleFrame = -1;
        for (var frame = 0; frame < scanFrameCount; frame++)
        {
            if (MathF.Abs(source[frame]) >= SilenceThreshold)
            {
                firstAudibleFrame = frame;
                break;
            }
        }

        if (firstAudibleFrame < 0)
        {
            return 0;
        }

        var prerollFrames = checked((int)Math.Ceiling(sampleRate * PreservedPrerollDurationSeconds));
        var trimFrames = Math.Max(0, firstAudibleFrame - prerollFrames);
        var minimumTrimFrames = checked((int)Math.Ceiling(sampleRate * MinimumTrimDurationSeconds));
        if (trimFrames < minimumTrimFrames || trimFrames >= source.Length)
        {
            return 0;
        }

        return trimFrames;
    }
}
