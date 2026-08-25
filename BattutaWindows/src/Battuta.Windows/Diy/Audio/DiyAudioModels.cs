using System.Collections.ObjectModel;

namespace Battuta.Windows.Diy.Audio;

public sealed record DiyAudioImportLimits(
    long MaximumSourceBytes = 25_165_824,
    long MaximumDecodedBytes = 64 * 1_024 * 1_024,
    double MinimumDurationSeconds = 0.005,
    double MaximumDurationSeconds = 5,
    int MinimumSampleRate = 1_000,
    int MaximumSampleRate = 384_000,
    int MaximumChannelCount = 8)
{
    public static DiyAudioImportLimits SoundPack { get; } = new();
}

public sealed record NormalizedDiyAudioInfo(
    double DurationSeconds,
    long ByteCount,
    int SampleRate,
    int ChannelCount,
    int BitsPerSample);

public sealed record PreparedDiyAudio(
    string AssetId,
    string NormalizedFilePath,
    string OriginalFileName,
    NormalizedDiyAudioInfo AudioInfo);

public sealed class DiyAudioException : Exception
{
    public DiyAudioException(string message)
        : base(message)
    {
    }

    public DiyAudioException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

public sealed record AudioSplitConfiguration(
    double MinimumDurationSeconds = 0.030,
    double MaximumDurationSeconds = 15,
    long MaximumSourceBytes = 64 * 1_024 * 1_024,
    long MaximumDecodedBytes = 64 * 1_024 * 1_024,
    int MinimumSampleRate = 1_000,
    int MaximumSampleRate = 384_000,
    int MaximumChannelCount = 32,
    double MinimumSegmentDurationSeconds = 0.012,
    double AnalysisWindowDurationSeconds = 0.004,
    double AnalysisHopDurationSeconds = 0.001,
    double MinimumReleaseDelaySeconds = 0.055,
    int WaveformPointCount = 256,
    int EnvelopePointCount = 512);

public enum AudioSplitWarning
{
    LowConfidence,
    FallbackValleyUsed,
    PossibleAdditionalKeystroke,
    SourceMayBeClipped,
}

public sealed record AudioWaveformPoint(
    double TimeSeconds,
    float Minimum,
    float Maximum,
    float RootMeanSquare);

public sealed record AudioEnergyEnvelopePoint(
    double TimeSeconds,
    float RootMeanSquare,
    float Peak,
    float RootMeanSquareDbfs,
    float PeakDbfs);

public sealed record AudioSplitSegmentPreview(
    double StartTimeSeconds,
    double EndTimeSeconds,
    double DurationSeconds,
    double TransientOffsetSeconds,
    float Peak,
    float RootMeanSquare,
    float PeakDbfs,
    float RootMeanSquareDbfs);

public sealed record AudioSplitSuggestion(
    double SplitTimeSeconds,
    double PressTransientTimeSeconds,
    double ValleyTimeSeconds,
    double ReleaseTransientTimeSeconds,
    double? SuggestedReleaseEndTimeSeconds,
    float Confidence,
    bool UsedFallback);

public sealed record AudioSplitAnalysis(
    string SourcePath,
    long SourceByteCount,
    double DurationSeconds,
    int SampleRate,
    int FrameCount,
    AudioSplitSuggestion Suggestion,
    AudioSplitSegmentPreview PressPreview,
    AudioSplitSegmentPreview ReleasePreview,
    IReadOnlyList<AudioWaveformPoint> Waveform,
    IReadOnlyList<AudioEnergyEnvelopePoint> EnergyEnvelope,
    IReadOnlySet<AudioSplitWarning> Warnings)
{
    internal static IReadOnlyList<T> Freeze<T>(List<T> values) =>
        new ReadOnlyCollection<T>(values);
}

public sealed record AudioSplitExportResult(
    string PressPath,
    string ReleasePath,
    double SplitTimeSeconds,
    double ReleaseEndTimeSeconds,
    int PressFrameCount,
    int ReleaseFrameCount,
    int SampleRate);
