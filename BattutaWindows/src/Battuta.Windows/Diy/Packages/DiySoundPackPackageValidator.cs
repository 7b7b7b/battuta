using System.IO;
using Battuta.Core.SoundPacks;
using Battuta.Windows.Diy.Audio;

namespace Battuta.Windows.Diy.Packages;

public sealed class DiySoundPackPackageValidator
{
    private readonly SoundPackValidationLimits _limits;

    public DiySoundPackPackageValidator(SoundPackValidationLimits? limits = null)
    {
        _limits = limits ?? SoundPackValidationLimits.Standard;
    }

    public ValidatedDiySoundPack Validate(string packagePath)
    {
        var root = DiySoundPackFileSafety.CanonicalPath(packagePath);
        DiySoundPackFileSafety.ValidatePackageRoot(root);

        var manifestPath = Path.Combine(root, "manifest.json");
        var manifestLength = DiySoundPackFileSafety.ValidateRegularFile(
            manifestPath,
            _limits.MaximumManifestBytes);
        if (manifestLength > int.MaxValue)
        {
            Throw(SoundPackErrorKind.SizeLimitExceeded, "manifest.json is too large.");
        }

        var manifestData = ReadBoundedManifest(manifestPath);
        var manifest = SoundPackManifestJson.Decode(manifestData, _limits);
        SoundPackValidator.Validate(manifest, _limits);

        var expectedAssets = manifest.Assets.Values
            .Select(asset => asset.RelativePath)
            .ToHashSet(StringComparer.Ordinal);
        var discoveredAssets = new HashSet<string>(StringComparer.Ordinal);
        var physicalPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var licenseFiles = new Dictionary<string, string>(StringComparer.Ordinal);
        long totalBytes = 0;
        var entryCount = 0;

        var pendingDirectories = new Stack<string>();
        pendingDirectories.Push(root);
        while (pendingDirectories.Count > 0)
        {
            var directory = pendingDirectories.Pop();
            foreach (var entry in Directory.EnumerateFileSystemEntries(directory))
            {
                entryCount++;
                if (entryCount > _limits.MaximumFileCount)
                {
                    Throw(
                        SoundPackErrorKind.SizeLimitExceeded,
                        $"Package entry count exceeds {_limits.MaximumFileCount}.");
                }

                var logicalPath = DiySoundPackFileSafety.RelativeLogicalPath(root, entry);
                if (!physicalPaths.Add(logicalPath))
                {
                    Throw(SoundPackErrorKind.UnsafePath, $"Case-insensitive duplicate path: {logicalPath}");
                }

                var attributes = File.GetAttributes(entry);
                if ((attributes & (FileAttributes.ReparsePoint | FileAttributes.Device)) != 0)
                {
                    Throw(SoundPackErrorKind.UnsafeFile, $"Unsafe package entry: {logicalPath}");
                }

                if ((attributes & FileAttributes.Directory) != 0)
                {
                    var allowedDirectory = logicalPath == "assets" ||
                        logicalPath == "licenses" ||
                        logicalPath.StartsWith("licenses/", StringComparison.Ordinal);
                    if (!allowedDirectory)
                    {
                        Throw(SoundPackErrorKind.UnsafePath, $"Unknown package directory: {logicalPath}");
                    }

                    pendingDirectories.Push(entry);
                    continue;
                }

                var byteCount = DiySoundPackFileSafety.ValidateRegularFile(
                    entry,
                    _limits.MaximumAssetBytes);
                try
                {
                    totalBytes = checked(totalBytes + byteCount);
                }
                catch (OverflowException error)
                {
                    throw new SoundPackException(
                        SoundPackErrorKind.SizeLimitExceeded,
                        "Package byte count overflowed.",
                        error);
                }

                if (totalBytes > _limits.MaximumPackBytes)
                {
                    Throw(SoundPackErrorKind.SizeLimitExceeded, "The sound pack is larger than 128 MiB.");
                }

                if (logicalPath == "manifest.json")
                {
                    continue;
                }

                if (expectedAssets.Contains(logicalPath))
                {
                    discoveredAssets.Add(logicalPath);
                    continue;
                }

                if (logicalPath.StartsWith("licenses/", StringComparison.Ordinal))
                {
                    var relativeName = logicalPath["licenses/".Length..];
                    licenseFiles.Add(relativeName, entry);
                    continue;
                }

                if (string.Equals(Path.GetFileName(logicalPath), ".DS_Store", StringComparison.Ordinal))
                {
                    continue;
                }

                Throw(SoundPackErrorKind.UnsafePath, $"Unknown package file: {logicalPath}");
            }
        }

        if (!discoveredAssets.SetEquals(expectedAssets))
        {
            var missing = expectedAssets.Except(discoveredAssets).Order().ToArray();
            Throw(SoundPackErrorKind.MissingAsset, $"Missing package assets: {string.Join(", ", missing)}");
        }

        var audioLimits = new DiyAudioImportLimits(
            MaximumSourceBytes: _limits.MaximumAssetBytes,
            MinimumDurationSeconds: _limits.MinimumAudioDurationSeconds,
            MaximumDurationSeconds: _limits.MaximumAudioDurationSeconds);
        var assetFiles = new Dictionary<SoundPackAssetId, string>();
        foreach (var asset in manifest.Assets.Values)
        {
            var assetPath = DiySoundPackFileSafety.DescendantPath(root, asset.RelativePath);
            var info = Pcm16WaveFile.ValidateNormalized(assetPath, audioLimits);
            if (info.ByteCount != asset.ByteCount ||
                Math.Abs(info.DurationSeconds - asset.DurationSeconds) >= 0.002)
            {
                Throw(SoundPackErrorKind.InvalidAudio, $"Audio metadata mismatch: {asset.RelativePath}");
            }

            var hash = Pcm16WaveFile.Sha256(assetPath, _limits.MaximumAssetBytes);
            if (!string.Equals(hash, asset.Sha256, StringComparison.Ordinal))
            {
                Throw(SoundPackErrorKind.HashMismatch, $"Audio hash mismatch: {asset.RelativePath}");
            }

            assetFiles.Add(asset.Id, assetPath);
        }

        return new ValidatedDiySoundPack(manifest, root, assetFiles, licenseFiles);
    }

    private static void Throw(SoundPackErrorKind kind, string message) =>
        throw new SoundPackException(kind, message);

    private byte[] ReadBoundedManifest(string path)
    {
        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            64 * 1_024,
            FileOptions.SequentialScan);
        if (stream.Length < 0 || stream.Length > _limits.MaximumManifestBytes || stream.Length > int.MaxValue)
        {
            Throw(SoundPackErrorKind.SizeLimitExceeded, "manifest.json is too large.");
        }

        var data = new byte[checked((int)stream.Length)];
        stream.ReadExactly(data);
        if (stream.ReadByte() != -1)
        {
            Throw(SoundPackErrorKind.SizeLimitExceeded, "manifest.json changed while it was being read.");
        }
        return data;
    }
}
