using Battuta.Core.Audio;
using Battuta.Core.Input;
using Battuta.Core.SoundPacks;

namespace Battuta.Core.Tests.SoundPacks;

internal static class SoundPackTestData
{
    internal static readonly DateTimeOffset FixedDate =
        new(2026, 8, 24, 9, 30, 15, TimeSpan.Zero);

    internal static SoundPackAssetId Id(char value) => new(new string(value, 64));

    internal static SoundPackAudioAsset Asset(
        SoundPackAssetId id,
        double duration = 0.1,
        long byteCount = 9_644) => new()
        {
            Id = id,
            RelativePath = $"assets/{id.Value}.wav",
            Sha256 = id.Value,
            OriginalFilename = "sample.wav",
            DurationSeconds = duration,
            SampleRate = 48_000,
            ChannelCount = 1,
            ByteCount = byteCount,
        };

    internal static SoundPackManifest Manifest(
        SoundPackPhaseAssignments? press = null,
        SoundPackPhaseAssignments? release = null,
        IEnumerable<SoundPackAssetId>? ids = null) => new()
        {
            Id = Guid.Parse("70a5acfe-9170-4d11-a313-ab988009428c"),
            Name = "Test pack",
            Author = "Battuta",
            Family = "DIY",
            Tone = "测试",
            Notes = "Round trip",
            BaseProfileId = SwitchProfiles.HolyPanda.Value,
            LayoutId = KeyboardLayoutCatalog.DefaultLayoutId,
            CreatedAt = FixedDate,
            ModifiedAt = FixedDate,
            Press = press ?? new SoundPackPhaseAssignments(),
            Release = release ?? new SoundPackPhaseAssignments(),
            Assets = (ids ?? []).ToDictionary(id => id.Value, id => Asset(id), StringComparer.Ordinal),
            Attributions = [],
        };
}
