using System.Text.Json.Serialization;
using Battuta.Core.Audio;
using Battuta.Core.Input;

namespace Battuta.Core.SoundPacks;

[JsonConverter(typeof(SoundPackAssetIdJsonConverter))]
public readonly record struct SoundPackAssetId
{
    public SoundPackAssetId(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        Value = value;
    }

    public string Value { get; }
    public override string ToString() => Value ?? string.Empty;
}

public enum SoundPackKeyOverrideKind
{
    Inherit,
    Silent,
    Asset,
}

[JsonConverter(typeof(SoundPackKeyOverrideJsonConverter))]
public sealed record SoundPackKeyOverride
{
    private SoundPackKeyOverride(SoundPackKeyOverrideKind kind, SoundPackAssetId? assetId)
    {
        Kind = kind;
        AssetId = assetId;
    }

    public SoundPackKeyOverrideKind Kind { get; }
    public SoundPackAssetId? AssetId { get; }

    public static SoundPackKeyOverride Inherit { get; } = new(SoundPackKeyOverrideKind.Inherit, null);
    public static SoundPackKeyOverride Silent { get; } = new(SoundPackKeyOverrideKind.Silent, null);
    public static SoundPackKeyOverride Asset(SoundPackAssetId assetId) =>
        new(SoundPackKeyOverrideKind.Asset, assetId);
}

public sealed record SoundPackPhaseAssignments
{
    [JsonPropertyName("generic")]
    public SoundPackAssetId? Generic { get; init; }

    [JsonPropertyName("rows")]
    [JsonRequired]
    public Dictionary<string, SoundPackAssetId> Rows { get; init; } = new(StringComparer.Ordinal);

    [JsonPropertyName("specials")]
    [JsonRequired]
    public Dictionary<string, SoundPackAssetId> Specials { get; init; } = new(StringComparer.Ordinal);

    /// <summary>
    /// Raw schema-v1 keys are intentional: unknown safe IDs must survive a load/save cycle.
    /// Use compatibility helpers rather than serializing PhysicalKeyId directly.
    /// </summary>
    [JsonPropertyName("keyOverrides")]
    [JsonRequired]
    public Dictionary<string, SoundPackKeyOverride> KeyOverrides { get; init; } = new(StringComparer.Ordinal);

    public SoundPackAssetId? AssetFor(KeyboardRowId row) =>
        Rows.TryGetValue(SoundPackV1WireNames.Row(row), out var assetId) ? assetId : null;

    public SoundPackAssetId? AssetFor(KeyboardSpecialKeyId specialKey) =>
        Specials.TryGetValue(SoundPackV1WireNames.Special(specialKey), out var assetId) ? assetId : null;

    public SoundPackKeyOverride? OverrideFor(PhysicalKeyId key)
    {
        foreach (var candidate in SoundPackV1KeyCompatibility.OverrideLookupIds(key))
        {
            if (KeyOverrides.TryGetValue(candidate, out var value))
            {
                return value;
            }
        }

        return null;
    }

    public bool TrySetOverride(PhysicalKeyId key, SoundPackKeyOverride? value)
    {
        if (!SoundPackV1KeyCompatibility.TryGetLegacyId(key, out var legacyId))
        {
            return false;
        }

        foreach (var candidate in SoundPackV1KeyCompatibility.OverrideLookupIds(key))
        {
            KeyOverrides.Remove(candidate);
        }

        if (value is not null)
        {
            KeyOverrides[legacyId] = value;
        }

        return true;
    }

    public IReadOnlySet<SoundPackAssetId> ReferencedAssetIds()
    {
        var result = Rows.Values.ToHashSet();
        result.UnionWith(Specials.Values);
        if (Generic.HasValue)
        {
            result.Add(Generic.Value);
        }

        foreach (var value in KeyOverrides.Values)
        {
            if (value.Kind == SoundPackKeyOverrideKind.Asset && value.AssetId.HasValue)
            {
                result.Add(value.AssetId.Value);
            }
        }

        return result;
    }
}

public sealed record SoundPackAssetLicense
{
    [JsonPropertyName("name")]
    [JsonRequired]
    public string Name { get; init; } = string.Empty;

    [JsonPropertyName("sourceURL")]
    public string? SourceUrl { get; init; }

    [JsonPropertyName("author")]
    public string? Author { get; init; }

    [JsonPropertyName("notice")]
    public string? Notice { get; init; }
}

public sealed record SoundPackAudioAsset
{
    [JsonPropertyName("id")]
    [JsonRequired]
    public SoundPackAssetId Id { get; init; }

    [JsonPropertyName("relativePath")]
    [JsonRequired]
    public string RelativePath { get; init; } = string.Empty;

    [JsonPropertyName("sha256")]
    [JsonRequired]
    public string Sha256 { get; init; } = string.Empty;

    [JsonPropertyName("originalFilename")]
    public string? OriginalFilename { get; init; }

    [JsonPropertyName("durationSeconds")]
    [JsonRequired]
    public double DurationSeconds { get; init; }

    [JsonPropertyName("sampleRate")]
    [JsonRequired]
    public int SampleRate { get; init; } = 48_000;

    [JsonPropertyName("channelCount")]
    [JsonRequired]
    public int ChannelCount { get; init; } = 1;

    [JsonPropertyName("byteCount")]
    [JsonRequired]
    public long ByteCount { get; init; }

    [JsonPropertyName("license")]
    public SoundPackAssetLicense? License { get; init; }
}

public sealed record SoundPackAttribution
{
    [JsonPropertyName("title")]
    [JsonRequired]
    public string Title { get; init; } = string.Empty;

    [JsonPropertyName("author")]
    public string? Author { get; init; }

    [JsonPropertyName("sourceURL")]
    public string? SourceUrl { get; init; }

    [JsonPropertyName("licenseName")]
    public string? LicenseName { get; init; }

    [JsonPropertyName("notice")]
    public string? Notice { get; init; }
}

public sealed record SoundPackManifest
{
    public const int CurrentSchemaVersion = 1;

    [JsonPropertyName("schemaVersion")]
    [JsonRequired]
    public int SchemaVersion { get; init; } = CurrentSchemaVersion;

    [JsonPropertyName("id")]
    [JsonRequired]
    public Guid Id { get; init; } = Guid.NewGuid();

    [JsonPropertyName("name")]
    [JsonRequired]
    public string Name { get; init; } = string.Empty;

    [JsonPropertyName("author")]
    public string? Author { get; init; }

    [JsonPropertyName("family")]
    public string? Family { get; init; }

    [JsonPropertyName("tone")]
    public string? Tone { get; init; }

    [JsonPropertyName("notes")]
    public string? Notes { get; init; }

    [JsonPropertyName("baseProfileID")]
    public string? BaseProfileId { get; init; }

    [JsonPropertyName("layoutID")]
    [JsonRequired]
    public string LayoutId { get; init; } = KeyboardLayoutCatalog.DefaultLayoutId;

    [JsonPropertyName("createdAt")]
    [JsonRequired]
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;

    [JsonPropertyName("modifiedAt")]
    [JsonRequired]
    public DateTimeOffset ModifiedAt { get; init; } = DateTimeOffset.UtcNow;

    [JsonPropertyName("press")]
    [JsonRequired]
    public SoundPackPhaseAssignments Press { get; init; } = new();

    [JsonPropertyName("release")]
    [JsonRequired]
    public SoundPackPhaseAssignments Release { get; init; } = new();

    [JsonPropertyName("assets")]
    [JsonRequired]
    public Dictionary<string, SoundPackAudioAsset> Assets { get; init; } = new(StringComparer.Ordinal);

    [JsonPropertyName("attributions")]
    [JsonRequired]
    public List<SoundPackAttribution> Attributions { get; init; } = [];

    public SoundPackPhaseAssignments AssignmentsFor(KeySoundPhase phase) =>
        phase == KeySoundPhase.Press ? Press : Release;

    public IReadOnlySet<SoundPackAssetId> ReferencedAssetIds() =>
        Press.ReferencedAssetIds().Union(Release.ReferencedAssetIds()).ToHashSet();
}

public sealed record SoundPackDescriptor(
    string SelectionId,
    string Name,
    string Family,
    string Tone,
    bool IsReadOnly,
    Guid? CustomPackId);

public static class SoundPackDescriptors
{
    public static IReadOnlyList<SoundPackDescriptor> BundledDefaults { get; } =
        SwitchProfileCatalog.All.Select(profile => new SoundPackDescriptor(
            profile.Id.Value,
            profile.DisplayName,
            profile.Family,
            profile.Tone,
            IsReadOnly: true,
            CustomPackId: null)).ToArray();

    public static SoundPackDescriptor BundledPack(SoundPackManifest manifest)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        return new SoundPackDescriptor(
            $"custom:{manifest.Id:D}".ToLowerInvariant(),
            manifest.Name,
            manifest.Family ?? "DIY",
            manifest.Tone ?? "自定义音色",
            IsReadOnly: true,
            CustomPackId: manifest.Id);
    }

    public static SoundPackDescriptor Custom(SoundPackManifest manifest)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        return new SoundPackDescriptor(
            $"custom:{manifest.Id:D}".ToLowerInvariant(),
            manifest.Name,
            manifest.Family ?? "DIY",
            manifest.Tone ?? "自定义音色",
            IsReadOnly: false,
            CustomPackId: manifest.Id);
    }
}
