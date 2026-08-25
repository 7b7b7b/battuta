using Battuta.Core.Audio;
using Battuta.Core.Input;
using Battuta.Core.SoundPacks;
using System.Globalization;

namespace Battuta.Core.Tests.SoundPacks;

public sealed class SoundPackValidatorTests
{
    [Fact]
    public void CompleteSchemaOneFixtureIsValid()
    {
        var id = SoundPackTestData.Id('a');
        var press = new SoundPackPhaseAssignments { Generic = id };
        press.Rows["R2"] = id;
        press.Specials["space"] = id;
        press.KeyOverrides["a"] = SoundPackKeyOverride.Asset(id);
        press.KeyOverrides["未来.key-1"] = SoundPackKeyOverride.Inherit;
        var manifest = SoundPackTestData.Manifest(press: press, ids: [id]);

        SoundPackValidator.Validate(manifest);
    }

    [Fact]
    public void MissingReferencedAssetIsRejected()
    {
        var id = SoundPackTestData.Id('a');
        var press = new SoundPackPhaseAssignments { Generic = id };
        var manifest = SoundPackTestData.Manifest(press: press);

        var exception = Assert.Throws<SoundPackException>(() => SoundPackValidator.Validate(manifest));
        Assert.Equal(SoundPackErrorKind.MissingAsset, exception.Kind);
    }

    [Theory]
    [InlineData("R99", null)]
    [InlineData(null, "future-special")]
    public void UnknownRowsAndSpecialsAreRejected(string? row, string? special)
    {
        var id = SoundPackTestData.Id('a');
        var press = new SoundPackPhaseAssignments();
        if (row is not null)
        {
            press.Rows[row] = id;
        }
        if (special is not null)
        {
            press.Specials[special] = id;
        }
        var manifest = SoundPackTestData.Manifest(press: press, ids: [id]);

        var exception = Assert.Throws<SoundPackException>(() => SoundPackValidator.Validate(manifest));
        Assert.Equal(SoundPackErrorKind.InvalidManifest, exception.Kind);
    }

    [Fact]
    public void UnknownLayoutAndBaseProfileAreRejected()
    {
        var layout = SoundPackTestData.Manifest() with { LayoutId = "windows-ansi-v1" };
        Assert.Equal(
            SoundPackErrorKind.InvalidManifest,
            Assert.Throws<SoundPackException>(() => SoundPackValidator.Validate(layout)).Kind);

        var profile = SoundPackTestData.Manifest() with { BaseProfileId = "future-profile" };
        Assert.Equal(
            SoundPackErrorKind.InvalidManifest,
            Assert.Throws<SoundPackException>(() => SoundPackValidator.Validate(profile)).Kind);
    }

    [Fact]
    public void UnsupportedSchemaIsReportedSeparately()
    {
        var manifest = SoundPackTestData.Manifest() with { SchemaVersion = 2 };
        var exception = Assert.Throws<SoundPackException>(() => SoundPackValidator.Validate(manifest));
        Assert.Equal(SoundPackErrorKind.UnsupportedSchema, exception.Kind);
    }

    [Theory]
    [InlineData("../escape.wav")]
    [InlineData("/absolute.wav")]
    [InlineData("assets\\escape.wav")]
    [InlineData("assets//sample.wav")]
    [InlineData("assets/./sample.wav")]
    [InlineData("assets/../sample.wav")]
    public void UnsafeRelativePathsAreRejected(string path)
    {
        var exception = Assert.Throws<SoundPackException>(() =>
            SoundPackPathValidator.ValidateRelativePath(path));
        Assert.Equal(SoundPackErrorKind.UnsafePath, exception.Kind);
    }

    [Fact]
    public void AssetPathMustBeContentAddressedCanonicalWav()
    {
        var id = SoundPackTestData.Id('a');
        var asset = SoundPackTestData.Asset(id) with { RelativePath = "../escape.wav" };
        var manifest = SoundPackTestData.Manifest(ids: [id]);
        manifest.Assets[id.Value] = asset;

        var exception = Assert.Throws<SoundPackException>(() => SoundPackValidator.Validate(manifest));
        Assert.Equal(SoundPackErrorKind.UnsafePath, exception.Kind);
    }

    [Theory]
    [InlineData(0.004, 9_644, 48_000, 1, SoundPackErrorKind.InvalidAudio)]
    [InlineData(5.001, 9_644, 48_000, 1, SoundPackErrorKind.InvalidAudio)]
    [InlineData(0.1, 0, 48_000, 1, SoundPackErrorKind.SizeLimitExceeded)]
    [InlineData(0.1, 9_644, 44_100, 1, SoundPackErrorKind.InvalidAudio)]
    [InlineData(0.1, 9_644, 48_000, 2, SoundPackErrorKind.InvalidAudio)]
    public void AudioMetadataLimitsAreEnforced(
        double duration,
        long bytes,
        int sampleRate,
        int channels,
        SoundPackErrorKind expectedKind)
    {
        var id = SoundPackTestData.Id('a');
        var asset = SoundPackTestData.Asset(id) with
        {
            DurationSeconds = duration,
            ByteCount = bytes,
            SampleRate = sampleRate,
            ChannelCount = channels,
        };
        var manifest = SoundPackTestData.Manifest(ids: [id]);
        manifest.Assets[id.Value] = asset;

        var exception = Assert.Throws<SoundPackException>(() => SoundPackValidator.Validate(manifest));
        Assert.Equal(expectedKind, exception.Kind);
    }

    [Fact]
    public void NonFiniteDurationAndExcessiveTotalDurationAreRejected()
    {
        var id = SoundPackTestData.Id('a');
        var nonFinite = SoundPackTestData.Manifest(ids: [id]);
        nonFinite.Assets[id.Value] = SoundPackTestData.Asset(id) with
        {
            DurationSeconds = double.NaN,
        };
        Assert.Equal(
            SoundPackErrorKind.InvalidAudio,
            Assert.Throws<SoundPackException>(() => SoundPackValidator.Validate(nonFinite)).Kind);

        var ids = Enumerable.Range(1, 37)
            .Select(index => new SoundPackAssetId(index.ToString("x64", CultureInfo.InvariantCulture)))
            .ToArray();
        var excessive = SoundPackTestData.Manifest(ids: ids);
        foreach (var assetId in ids)
        {
            excessive.Assets[assetId.Value] = SoundPackTestData.Asset(assetId, duration: 5);
        }
        Assert.Equal(
            SoundPackErrorKind.SizeLimitExceeded,
            Assert.Throws<SoundPackException>(() => SoundPackValidator.Validate(excessive)).Kind);
    }

    [Fact]
    public void HashMustBeLowercaseAndMatchDictionaryAndPath()
    {
        var id = SoundPackTestData.Id('a');
        var uppercase = new SoundPackAssetId(id.Value.ToUpperInvariant());
        var manifest = SoundPackTestData.Manifest();
        manifest.Assets[uppercase.Value] = SoundPackTestData.Asset(uppercase) with
        {
            Sha256 = uppercase.Value,
        };

        var exception = Assert.Throws<SoundPackException>(() => SoundPackValidator.Validate(manifest));
        Assert.Equal(SoundPackErrorKind.InvalidManifest, exception.Kind);
    }

    [Theory]
    [InlineData("")]
    [InlineData("../a")]
    [InlineData("bad/key")]
    [InlineData("space key")]
    public void UnsafeOverrideIdentifiersAreRejected(string key)
    {
        var press = new SoundPackPhaseAssignments();
        press.KeyOverrides[key] = SoundPackKeyOverride.Silent;
        var manifest = SoundPackTestData.Manifest(press: press);

        Assert.Equal(
            SoundPackErrorKind.InvalidManifest,
            Assert.Throws<SoundPackException>(() => SoundPackValidator.Validate(manifest)).Kind);
    }
}
