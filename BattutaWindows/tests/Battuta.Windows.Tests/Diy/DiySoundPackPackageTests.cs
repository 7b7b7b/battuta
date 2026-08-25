using System.IO;
using Battuta.Core.SoundPacks;
using Battuta.Windows.Diy.Audio;
using Battuta.Windows.Diy.Packages;

namespace Battuta.Windows.Tests.Diy;

public sealed class DiySoundPackPackageTests
{
    [Fact]
    public async Task LibraryAndArchiveRoundTripAndApplyCollisionPolicies()
    {
        using var root = new TemporaryDirectory();
        var source = WaveFixture.WriteStereoSine(root.Combine("source.wav"));
        using var importer = new DiyAudioImportService(root.Combine("normalized"));
        var prepared = await importer.PrepareImportAsync(source);
        var manifest = ManifestFor(prepared, "Round trip");
        using var library = new DiySoundPackLibrary(
            root.Combine("library"),
            builtInDescriptors: []);

        var descriptor = await library.SaveAsync(
            manifest,
            new Dictionary<SoundPackAssetId, string>
            {
                [new SoundPackAssetId(prepared.AssetId)] = prepared.NormalizedFilePath,
            });
        var loaded = await library.LoadAsync(manifest.Id);

        Assert.Equal(manifest.Id, descriptor.CustomPackId);
        Assert.Equal("Round trip", loaded.Manifest.Name);
        Assert.Equal(prepared.AssetId, WaveFixture.Sha256(
            loaded.AssetPath(new SoundPackAssetId(prepared.AssetId))));
        Assert.Single(await library.DescriptorsAsync());

        _ = await library.SaveAsync(loaded.Manifest with { Name = "Renamed" });
        Assert.Equal("Renamed", (await library.LoadAsync(manifest.Id)).Manifest.Name);

        var archive = new DiySoundPackArchiveService();
        var exportedPath = root.Combine("export.simuboardpack");
        _ = await archive.ExportAsync(manifest.Id, library, exportedPath);
        Assert.Equal("Renamed", archive.Validate(exportedPath).Manifest.Name);

        using var importedLibrary = new DiySoundPackLibrary(
            root.Combine("imported"),
            builtInDescriptors: []);
        var first = await archive.ImportAsync(exportedPath, importedLibrary);
        Assert.Equal(manifest.Id, first.CustomPackId);
        var duplicated = await archive.ImportAsync(exportedPath, importedLibrary);
        Assert.NotEqual(manifest.Id, duplicated.CustomPackId);
        Assert.Equal(2, (await importedLibrary.DescriptorsAsync()).Count);

        var collision = await Assert.ThrowsAsync<SoundPackException>(() => archive.ImportAsync(
            exportedPath,
            importedLibrary,
            SoundPackImportCollisionPolicy.Reject));
        Assert.Equal(SoundPackErrorKind.PackAlreadyExists, collision.Kind);
    }

    [Fact]
    public void ValidateAllowsManifestOnlyBlankPackage()
    {
        using var root = new TemporaryDirectory();
        var package = root.Combine("Blank.simuboardpack");
        Directory.CreateDirectory(package);
        File.WriteAllBytes(
            Path.Combine(package, "manifest.json"),
            SoundPackManifestJson.Encode(new SoundPackManifest { Name = "Blank" }));

        var validated = new DiySoundPackPackageValidator().Validate(package);

        Assert.Empty(validated.AssetFiles);
        Assert.Equal("Blank", validated.Manifest.Name);
    }

    [Fact]
    public async Task ValidateRejectsUnknownFileAndHashTampering()
    {
        using var root = new TemporaryDirectory();
        var source = WaveFixture.WriteStereoSine(root.Combine("source.wav"));
        using var importer = new DiyAudioImportService(root.Combine("normalized"));
        var prepared = await importer.PrepareImportAsync(source);
        var manifest = ManifestFor(prepared, "Security");
        using var library = new DiySoundPackLibrary(
            root.Combine("library"),
            builtInDescriptors: []);
        _ = await library.SaveAsync(
            manifest,
            new Dictionary<SoundPackAssetId, string>
            {
                [new SoundPackAssetId(prepared.AssetId)] = prepared.NormalizedFilePath,
            });
        var archive = new DiySoundPackArchiveService();
        var package = root.Combine("security.simuboardpack");
        _ = await archive.ExportAsync(manifest.Id, library, package);

        await File.WriteAllTextAsync(Path.Combine(package, "unexpected.txt"), "not allowed");
        var unknown = Assert.Throws<SoundPackException>(() => archive.Validate(package));
        Assert.Equal(SoundPackErrorKind.UnsafePath, unknown.Kind);
        File.Delete(Path.Combine(package, "unexpected.txt"));

        var assetPath = Path.Combine(package, "assets", $"{prepared.AssetId}.wav");
        await File.AppendAllTextAsync(assetPath, "tamper");
        var tampered = Assert.Throws<SoundPackException>(() => archive.Validate(package));
        Assert.True(tampered.Kind is SoundPackErrorKind.HashMismatch or SoundPackErrorKind.InvalidAudio);
    }

    [Fact]
    public async Task ValidateRejectsDirectoryReparsePointWhenSupported()
    {
        using var root = new TemporaryDirectory();
        var package = root.Combine("links.simuboardpack");
        Directory.CreateDirectory(package);
        File.WriteAllBytes(
            Path.Combine(package, "manifest.json"),
            SoundPackManifestJson.Encode(new SoundPackManifest { Name = "Links" }));
        var target = root.Combine("outside");
        Directory.CreateDirectory(target);
        var link = Path.Combine(package, "licenses");
        try
        {
            _ = Directory.CreateSymbolicLink(link, target);
        }
        catch (Exception error) when (
            error is UnauthorizedAccessException or IOException or PlatformNotSupportedException)
        {
            return;
        }

        var validator = new DiySoundPackPackageValidator();
        var rejected = Assert.Throws<SoundPackException>(() => validator.Validate(package));
        Assert.Equal(SoundPackErrorKind.UnsafeFile, rejected.Kind);
    }

    private static SoundPackManifest ManifestFor(PreparedDiyAudio prepared, string name)
    {
        var id = new SoundPackAssetId(prepared.AssetId);
        var asset = new SoundPackAudioAsset
        {
            Id = id,
            RelativePath = $"assets/{prepared.AssetId}.wav",
            Sha256 = prepared.AssetId,
            OriginalFilename = prepared.OriginalFileName,
            DurationSeconds = prepared.AudioInfo.DurationSeconds,
            SampleRate = prepared.AudioInfo.SampleRate,
            ChannelCount = prepared.AudioInfo.ChannelCount,
            ByteCount = prepared.AudioInfo.ByteCount,
        };
        return new SoundPackManifest
        {
            Name = name,
            Press = new SoundPackPhaseAssignments { Generic = id },
            Release = new SoundPackPhaseAssignments { Generic = id },
            Assets = new Dictionary<string, SoundPackAudioAsset>(StringComparer.Ordinal)
            {
                [id.Value] = asset,
            },
        };
    }
}
