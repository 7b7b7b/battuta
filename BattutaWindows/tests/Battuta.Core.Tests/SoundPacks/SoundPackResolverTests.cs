using Battuta.Core.Audio;
using Battuta.Core.Input;
using Battuta.Core.SoundPacks;

namespace Battuta.Core.Tests.SoundPacks;

public sealed class SoundPackResolverTests
{
    [Fact]
    public void ResolutionPriorityIsOverrideSpecialRowGeneric()
    {
        var overrideId = SoundPackTestData.Id('a');
        var specialId = SoundPackTestData.Id('b');
        var rowId = SoundPackTestData.Id('c');
        var genericId = SoundPackTestData.Id('d');
        var press = new SoundPackPhaseAssignments { Generic = genericId };
        press.Rows["R2"] = rowId;
        press.Specials["space"] = specialId;
        press.KeyOverrides["a"] = SoundPackKeyOverride.Asset(overrideId);
        var manifest = SoundPackTestData.Manifest(
            press: press,
            ids: [overrideId, specialId, rowId, genericId]);
        var resolver = new SoundPackResolver(manifest);

        AssertResolution(
            resolver.Resolve(PhysicalKeys.KeyA, KeySoundPhase.Press),
            overrideId,
            SoundPackResolutionSourceKind.KeyOverride);
        AssertResolution(
            resolver.Resolve(PhysicalKeys.Space, KeySoundPhase.Press),
            specialId,
            SoundPackResolutionSourceKind.Special);
        AssertResolution(
            resolver.Resolve(PhysicalKeys.KeyS, KeySoundPhase.Press),
            rowId,
            SoundPackResolutionSourceKind.Row);
        AssertResolution(
            resolver.Resolve(PhysicalKeys.KeyQ, KeySoundPhase.Press),
            genericId,
            SoundPackResolutionSourceKind.Generic);
    }

    [Fact]
    public void InheritContinuesButSilentTerminatesFallback()
    {
        var rowId = SoundPackTestData.Id('a');
        var press = new SoundPackPhaseAssignments();
        press.Rows["R2"] = rowId;
        press.KeyOverrides["a"] = SoundPackKeyOverride.Inherit;
        var manifest = SoundPackTestData.Manifest(press: press, ids: [rowId]);

        var inherited = new SoundPackResolver(manifest)
            .Resolve(PhysicalKeys.KeyA, KeySoundPhase.Press);
        AssertResolution(inherited, rowId, SoundPackResolutionSourceKind.Row);

        press.KeyOverrides["a"] = SoundPackKeyOverride.Silent;
        var silent = new SoundPackResolver(manifest)
            .Resolve(PhysicalKeys.KeyA, KeySoundPhase.Press);
        Assert.Equal(SoundPackResolutionKind.Silent, silent.Kind);
        Assert.Equal(SoundPackResolutionSourceKind.KeyOverride, silent.Source.Kind);
        Assert.Null(silent.AssetId);
    }

    [Fact]
    public void MissingAssignmentsRemainMissingForBuiltInPlaybackFallback()
    {
        var manifest = SoundPackTestData.Manifest() with
        {
            BaseProfileId = SwitchProfiles.MxClear.Value,
        };

        var resolution = new SoundPackResolver(manifest)
            .Resolve(PhysicalKeys.KeyA, KeySoundPhase.Release);

        Assert.Equal(SoundPackResolutionKind.Missing, resolution.Kind);
        Assert.Equal(SoundPackResolutionSourceKind.MissingAssignment, resolution.Source.Kind);
        var fallbackProfile = SwitchProfileCatalog.Get(SwitchProfiles.MxClear);
        Assert.Equal(
            KeySoundSample.GenericR2,
            KeySoundMapper.SampleFor(PhysicalKeys.KeyA, KeySoundPhase.Release, fallbackProfile));
    }

    [Fact]
    public void BrokenAssetReferenceIsNeverReturnedAsPlayable()
    {
        var missing = SoundPackTestData.Id('a');
        var press = new SoundPackPhaseAssignments();
        press.KeyOverrides["a"] = SoundPackKeyOverride.Asset(missing);
        var manifest = SoundPackTestData.Manifest(press: press);

        var resolution = new SoundPackResolver(manifest)
            .Resolve(PhysicalKeys.KeyA, KeySoundPhase.Press);

        Assert.Equal(SoundPackResolutionKind.Missing, resolution.Kind);
        Assert.Equal(SoundPackResolutionSourceKind.BrokenAssetReference, resolution.Source.Kind);
        Assert.Equal(missing, resolution.Source.BrokenAssetId);
    }

    [Fact]
    public void FunctionKeyParticipatesInLegacyDiyMapping()
    {
        var id = SoundPackTestData.Id('a');
        var press = new SoundPackPhaseAssignments { Generic = id };
        press.KeyOverrides["function"] = SoundPackKeyOverride.Silent;
        var manifest = SoundPackTestData.Manifest(press: press, ids: [id]);

        var resolution = new SoundPackResolver(manifest)
            .Resolve(PhysicalKeys.Fn, KeySoundPhase.Press);

        Assert.Equal(SoundPackResolutionKind.Silent, resolution.Kind);
        Assert.Equal(PhysicalKeys.Fn, resolution.Source.Key);
    }

    [Fact]
    public void UnknownPlatformFallbackCannotAddressDiyOverride()
    {
        var id = SoundPackTestData.Id('a');
        var press = new SoundPackPhaseAssignments { Generic = id };
        press.KeyOverrides["win.scan.e0.005E"] = SoundPackKeyOverride.Silent;
        var manifest = SoundPackTestData.Manifest(press: press, ids: [id]);

        var resolution = new SoundPackResolver(manifest)
            .Resolve(new PhysicalKeyId("win.scan.e0.005E"), KeySoundPhase.Press);

        Assert.Equal(SoundPackResolutionKind.Missing, resolution.Kind);
        Assert.Equal(SoundPackResolutionSourceKind.UnavailableKey, resolution.Source.Kind);
    }

    private static void AssertResolution(
        SoundPackResolution resolution,
        SoundPackAssetId expectedAsset,
        SoundPackResolutionSourceKind expectedSource)
    {
        Assert.Equal(SoundPackResolutionKind.Asset, resolution.Kind);
        Assert.Equal(expectedAsset, resolution.AssetId);
        Assert.Equal(expectedSource, resolution.Source.Kind);
    }
}
