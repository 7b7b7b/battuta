using Battuta.Core.Audio;
using Battuta.Core.Input;

namespace Battuta.Core.SoundPacks;

public enum SoundPackResolutionKind
{
    Asset,
    Silent,
    Missing,
}

public enum SoundPackResolutionSourceKind
{
    KeyOverride,
    Special,
    Row,
    Generic,
    UnavailableKey,
    MissingAssignment,
    BrokenAssetReference,
}

public sealed record SoundPackResolutionSource(
    SoundPackResolutionSourceKind Kind,
    PhysicalKeyId? Key = null,
    KeyboardSpecialKeyId? SpecialKey = null,
    KeyboardRowId? Row = null,
    SoundPackAssetId? BrokenAssetId = null);

public sealed record SoundPackResolution(
    SoundPackResolutionKind Kind,
    SoundPackAssetId? AssetId,
    SoundPackResolutionSource Source)
{
    public bool IsSilent => Kind == SoundPackResolutionKind.Silent;
}

public sealed class SoundPackResolver
{
    public SoundPackResolver(SoundPackManifest manifest)
    {
        Manifest = manifest ?? throw new ArgumentNullException(nameof(manifest));
    }

    public SoundPackManifest Manifest { get; }

    public SoundPackResolution Resolve(PhysicalKeyId key, KeySoundPhase phase)
    {
        if (!PhysicalKeyCatalog.TryGet(key, out var definition) || !definition.IsAssignable)
        {
            return Missing(new SoundPackResolutionSource(
                SoundPackResolutionSourceKind.UnavailableKey,
                Key: key));
        }

        var assignments = Manifest.AssignmentsFor(phase);
        var keyOverride = assignments.OverrideFor(key);
        if (keyOverride is not null)
        {
            var source = new SoundPackResolutionSource(
                SoundPackResolutionSourceKind.KeyOverride,
                Key: key);
            switch (keyOverride.Kind)
            {
                case SoundPackKeyOverrideKind.Inherit:
                    break;
                case SoundPackKeyOverrideKind.Silent:
                    return new SoundPackResolution(SoundPackResolutionKind.Silent, null, source);
                case SoundPackKeyOverrideKind.Asset when keyOverride.AssetId.HasValue:
                    return ResolveAsset(keyOverride.AssetId.Value, source);
                default:
                    return Missing(new SoundPackResolutionSource(
                        SoundPackResolutionSourceKind.BrokenAssetReference,
                        Key: key));
            }
        }

        if (definition.SpecialKey is { } specialKey
            && assignments.AssetFor(specialKey) is { } specialAsset)
        {
            return ResolveAsset(specialAsset, new SoundPackResolutionSource(
                SoundPackResolutionSourceKind.Special,
                SpecialKey: specialKey));
        }

        if (assignments.AssetFor(definition.Row) is { } rowAsset)
        {
            return ResolveAsset(rowAsset, new SoundPackResolutionSource(
                SoundPackResolutionSourceKind.Row,
                Row: definition.Row));
        }

        if (assignments.Generic is { } genericAsset)
        {
            return ResolveAsset(genericAsset, new SoundPackResolutionSource(
                SoundPackResolutionSourceKind.Generic));
        }

        return Missing(new SoundPackResolutionSource(
            SoundPackResolutionSourceKind.MissingAssignment));
    }

    private SoundPackResolution ResolveAsset(
        SoundPackAssetId assetId,
        SoundPackResolutionSource source)
    {
        if (!Manifest.Assets.ContainsKey(assetId.Value))
        {
            return Missing(new SoundPackResolutionSource(
                SoundPackResolutionSourceKind.BrokenAssetReference,
                Key: source.Key,
                SpecialKey: source.SpecialKey,
                Row: source.Row,
                BrokenAssetId: assetId));
        }

        return new SoundPackResolution(SoundPackResolutionKind.Asset, assetId, source);
    }

    private static SoundPackResolution Missing(SoundPackResolutionSource source) =>
        new(SoundPackResolutionKind.Missing, null, source);
}
