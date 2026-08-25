using System.IO;
using Battuta.Core.SoundPacks;

namespace Battuta.Windows.Diy.Packages;

public sealed class DiySoundPackArchiveService
{
    private readonly SoundPackValidationLimits _limits;
    private readonly DiySoundPackPackageValidator _validator;

    public DiySoundPackArchiveService(SoundPackValidationLimits? limits = null)
    {
        _limits = limits ?? SoundPackValidationLimits.Standard;
        _validator = new DiySoundPackPackageValidator(_limits);
    }

    public ValidatedDiySoundPack Validate(string packagePath) => _validator.Validate(packagePath);

    public async Task<SoundPackDescriptor> ImportAsync(
        string sourcePackagePath,
        DiySoundPackLibrary library,
        SoundPackImportCollisionPolicy collisionPolicy = SoundPackImportCollisionPolicy.Duplicate,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(library);
        var package = await Task.Run(
            () => _validator.Validate(sourcePackagePath),
            cancellationToken).ConfigureAwait(false);
        return await library.SaveImportedAsync(
            package.Manifest,
            package.AssetFiles,
            package.LicenseFiles,
            collisionPolicy,
            cancellationToken).ConfigureAwait(false);
    }

    public async Task<string> ExportAsync(
        Guid customPackId,
        DiySoundPackLibrary library,
        string requestedDestinationPath,
        bool overwriteExisting = false,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(library);
        var document = await library.LoadAsync(customPackId, cancellationToken).ConfigureAwait(false);
        return await ExportAsync(
            document,
            requestedDestinationPath,
            overwriteExisting,
            cancellationToken).ConfigureAwait(false);
    }

    public async Task<string> ExportAsync(
        DiySoundPackDocument document,
        string requestedDestinationPath,
        bool overwriteExisting = false,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(document);
        ArgumentException.ThrowIfNullOrWhiteSpace(requestedDestinationPath);
        return await Task.Run(
            () => ExportCore(
                document,
                requestedDestinationPath,
                overwriteExisting,
                cancellationToken),
            cancellationToken).ConfigureAwait(false);
    }

    private string ExportCore(
        DiySoundPackDocument document,
        string requestedDestinationPath,
        bool overwriteExisting,
        CancellationToken cancellationToken)
    {
        var sourcePackage = _validator.Validate(document.RootPath);
        var destination = requestedDestinationPath.EndsWith(
            ".simuboardpack",
            StringComparison.OrdinalIgnoreCase)
            ? Path.GetFullPath(requestedDestinationPath)
            : Path.GetFullPath(requestedDestinationPath + ".simuboardpack");
        DiySoundPackFileSafety.ValidatePackageRoot(destination, mustExist: false);
        if (DiySoundPackFileSafety.IsSameOrDescendant(document.RootPath, destination))
        {
            throw new SoundPackException(
                SoundPackErrorKind.UnsafePath,
                "The export destination cannot be inside the source package.");
        }

        var parent = Path.GetDirectoryName(destination)
            ?? throw new SoundPackException(
                SoundPackErrorKind.UnsafePath,
                "The export destination has no parent directory.");
        DiySoundPackFileSafety.EnsureSafeDirectory(parent, create: true);

        if (Directory.Exists(destination))
        {
            if (!overwriteExisting)
            {
                throw new SoundPackException(
                    SoundPackErrorKind.PackAlreadyExists,
                    $"A package already exists at {destination}.");
            }

            _ = _validator.Validate(destination);
        }
        else if (File.Exists(destination))
        {
            throw new SoundPackException(
                SoundPackErrorKind.UnsafeFile,
                "A regular file occupies the package export destination.");
        }

        var staging = Path.Combine(
            parent,
            $".simuboard-export-{Guid.NewGuid():N}.simuboardpack");
        Directory.CreateDirectory(staging);
        try
        {
            var manifestData = SoundPackManifestJson.Encode(sourcePackage.Manifest);
            File.WriteAllBytes(Path.Combine(staging, "manifest.json"), manifestData);
            foreach (var asset in sourcePackage.Manifest.Assets.Values)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var source = sourcePackage.AssetFiles[asset.Id];
                var target = DiySoundPackFileSafety.DescendantPath(staging, asset.RelativePath);
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                DiySoundPackFileSafety.CopyRegularFile(
                    source,
                    target,
                    _limits.MaximumAssetBytes);
            }

            foreach (var (relativeName, source) in sourcePackage.LicenseFiles)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var target = DiySoundPackFileSafety.DescendantPath(
                    staging,
                    $"licenses/{relativeName}");
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                DiySoundPackFileSafety.CopyRegularFile(
                    source,
                    target,
                    _limits.MaximumAssetBytes);
            }

            _ = _validator.Validate(staging);
            DiySoundPackDirectoryTransaction.Install(
                staging,
                destination,
                parent,
                replaceExisting: overwriteExisting && Directory.Exists(destination));
            return destination;
        }
        finally
        {
            if (Directory.Exists(staging))
            {
                DiySoundPackFileSafety.DeleteOwnedDirectory(parent, staging, ".simuboard-export-");
            }
        }
    }
}
