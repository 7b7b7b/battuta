using System.IO;
using Battuta.Core.SoundPacks;

namespace Battuta.Windows.Diy.Packages;

public enum SoundPackImportCollisionPolicy
{
    Duplicate,
    Replace,
    Reject,
}

public sealed record DiySoundPackDocument(
    SoundPackDescriptor Descriptor,
    SoundPackManifest Manifest,
    string RootPath)
{
    public string AssetPath(SoundPackAssetId assetId)
    {
        if (!Manifest.Assets.TryGetValue(assetId.Value, out var asset))
        {
            throw new SoundPackException(
                SoundPackErrorKind.MissingAsset,
                $"The sound pack is missing asset {assetId.Value}.");
        }

        return DiySoundPackFileSafety.DescendantPath(RootPath, asset.RelativePath);
    }
}

public sealed record ValidatedDiySoundPack(
    SoundPackManifest Manifest,
    string RootPath,
    IReadOnlyDictionary<SoundPackAssetId, string> AssetFiles,
    IReadOnlyDictionary<string, string> LicenseFiles);
