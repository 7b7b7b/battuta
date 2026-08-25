using System.Text;
using System.Text.Json;
using Battuta.Core.Input;
using Battuta.Core.SoundPacks;

namespace Battuta.Core.Tests.SoundPacks;

public sealed class SoundPackJsonTests
{
    [Fact]
    public void SchemaOneManifestRoundTripsExactOverrideShapesAndUnknownKeys()
    {
        var assetId = SoundPackTestData.Id('a');
        var press = new SoundPackPhaseAssignments();
        press.KeyOverrides["a"] = SoundPackKeyOverride.Asset(assetId);
        press.KeyOverrides["leftCommand"] = SoundPackKeyOverride.Silent;
        press.KeyOverrides["future.safe-key_1"] = SoundPackKeyOverride.Inherit;
        var manifest = SoundPackTestData.Manifest(press: press, ids: [assetId]);

        var json = SoundPackManifestJson.EncodeToString(manifest);
        using var document = JsonDocument.Parse(json);
        var overrides = document.RootElement.GetProperty("press").GetProperty("keyOverrides");
        Assert.Equal("asset", overrides.GetProperty("a").GetProperty("kind").GetString());
        Assert.Equal(assetId.Value, overrides.GetProperty("a").GetProperty("assetID").GetString());
        Assert.Equal("silent", overrides.GetProperty("leftCommand").GetProperty("kind").GetString());
        Assert.False(overrides.GetProperty("leftCommand").TryGetProperty("assetID", out _));
        Assert.Equal("inherit", overrides.GetProperty("future.safe-key_1").GetProperty("kind").GetString());
        Assert.Contains("2026-08-24T09:30:15Z", json, StringComparison.Ordinal);

        var decoded = SoundPackManifestJson.Decode(Encoding.UTF8.GetBytes(json));
        Assert.Equal(KeyboardLayoutCatalog.DefaultLayoutId, decoded.LayoutId);
        Assert.Equal(SoundPackKeyOverrideKind.Asset, decoded.Press.KeyOverrides["a"].Kind);
        Assert.Equal(assetId, decoded.Press.KeyOverrides["a"].AssetId);
        Assert.Equal(SoundPackKeyOverrideKind.Silent, decoded.Press.KeyOverrides["leftCommand"].Kind);
        Assert.Equal(SoundPackKeyOverrideKind.Inherit, decoded.Press.KeyOverrides["future.safe-key_1"].Kind);
    }

    [Fact]
    public void MissingRequiredAssignmentCollectionIsRejectedDuringDecode()
    {
        const string json = """
            {
              "schemaVersion": 1,
              "id": "70a5acfe-9170-4d11-a313-ab988009428c",
              "name": "Broken",
              "layoutID": "mac-ansi-tkl-v1",
              "createdAt": "2026-08-24T09:30:15Z",
              "modifiedAt": "2026-08-24T09:30:15Z",
              "press": { "generic": null, "specials": {}, "keyOverrides": {} },
              "release": { "generic": null, "rows": {}, "specials": {}, "keyOverrides": {} },
              "assets": {},
              "attributions": []
            }
            """;

        var exception = Assert.Throws<SoundPackException>(() =>
            SoundPackManifestJson.Decode(Encoding.UTF8.GetBytes(json)));
        Assert.Equal(SoundPackErrorKind.InvalidManifest, exception.Kind);
    }

    [Fact]
    public void AssetOverrideWithoutAssetIdIsRejected()
    {
        var json = SoundPackManifestJson.EncodeToString(SoundPackTestData.Manifest());
        json = json.Replace(
            "\"keyOverrides\": {}",
            "\"keyOverrides\": { \"a\": { \"kind\": \"asset\" } }",
            StringComparison.Ordinal);

        var exception = Assert.Throws<SoundPackException>(() =>
            SoundPackManifestJson.Decode(Encoding.UTF8.GetBytes(json)));
        Assert.Equal(SoundPackErrorKind.InvalidManifest, exception.Kind);
    }

    [Fact]
    public void ManifestByteLimitIsCheckedBeforeJsonParsing()
    {
        var limits = SoundPackValidationLimits.Standard with { MaximumManifestBytes = 16 };
        var exception = Assert.Throws<SoundPackException>(() =>
            SoundPackManifestJson.Decode(new byte[17], limits));
        Assert.Equal(SoundPackErrorKind.SizeLimitExceeded, exception.Kind);
    }

    [Fact]
    public void EditingKnownOverrideWritesLegacyIdAndPreservesUnknownEntries()
    {
        var assignments = new SoundPackPhaseAssignments();
        assignments.KeyOverrides["future.safe"] = SoundPackKeyOverride.Silent;
        assignments.KeyOverrides["KeyA"] = SoundPackKeyOverride.Inherit;

        Assert.True(assignments.TrySetOverride(PhysicalKeys.KeyA, SoundPackKeyOverride.Silent));
        Assert.Equal(SoundPackKeyOverrideKind.Silent, assignments.KeyOverrides["a"].Kind);
        Assert.False(assignments.KeyOverrides.ContainsKey("KeyA"));
        Assert.True(assignments.KeyOverrides.ContainsKey("future.safe"));
        Assert.False(assignments.TrySetOverride(
            new PhysicalKeyId("win.scan.base.0070"), SoundPackKeyOverride.Silent));
    }

    [Fact]
    public void LegacyOverrideWinsOverToleratedCanonicalAlias()
    {
        var assignments = new SoundPackPhaseAssignments();
        assignments.KeyOverrides["a"] = SoundPackKeyOverride.Silent;
        assignments.KeyOverrides["KeyA"] = SoundPackKeyOverride.Inherit;

        Assert.Equal(SoundPackKeyOverrideKind.Silent, assignments.OverrideFor(PhysicalKeys.KeyA)?.Kind);
    }

    [Fact]
    public void DescriptorCatalogExposesAllBundledAndStableCustomSelections()
    {
        Assert.Equal(20, SoundPackDescriptors.BundledDefaults.Count);
        Assert.All(SoundPackDescriptors.BundledDefaults, descriptor =>
        {
            Assert.True(descriptor.IsReadOnly);
            Assert.Null(descriptor.CustomPackId);
        });

        var custom = SoundPackDescriptors.Custom(SoundPackTestData.Manifest());
        Assert.Equal("custom:70a5acfe-9170-4d11-a313-ab988009428c", custom.SelectionId);
        Assert.False(custom.IsReadOnly);
    }
}
