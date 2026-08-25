using System.IO;
using Battuta.Core.SoundPacks;
using Battuta.Windows.Diy.Audio;

namespace Battuta.Windows.Diy.Packages;

public sealed class DiySoundPackLibrary : IDisposable
{
    private readonly SoundPackValidationLimits _limits;
    private readonly DiySoundPackPackageValidator _packageValidator;
    private readonly IReadOnlyList<SoundPackDescriptor> _builtInDescriptors;
    private readonly string? _bundledPackRootPath;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public DiySoundPackLibrary(
        string? rootPath = null,
        IReadOnlyList<SoundPackDescriptor>? builtInDescriptors = null,
        string? bundledPackRootPath = null,
        SoundPackValidationLimits? limits = null)
    {
        RootPath = DiySoundPackFileSafety.CanonicalPath(rootPath ?? DefaultRootPath());
        _builtInDescriptors = builtInDescriptors ?? SoundPackDescriptors.BundledDefaults;
        _bundledPackRootPath = bundledPackRootPath is null
            ? DefaultBundledPackRootPath()
            : DiySoundPackFileSafety.CanonicalPath(bundledPackRootPath);
        _limits = limits ?? SoundPackValidationLimits.Standard;
        _packageValidator = new DiySoundPackPackageValidator(_limits);
    }

    public string RootPath { get; }

    public string PackPath(Guid id) => Path.Combine(
        RootPath,
        $"{id:D}.simuboardpack".ToLowerInvariant());

    public async Task<IReadOnlyList<SoundPackDescriptor>> DescriptorsAsync(
        CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            return await Task.Run(
                () => DescriptorsCore(cancellationToken),
                cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<DiySoundPackDocument> LoadAsync(
        Guid id,
        CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            return await Task.Run(
                () => LoadCore(id),
                cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<SoundPackDescriptor> SaveAsync(
        SoundPackManifest manifest,
        IReadOnlyDictionary<SoundPackAssetId, string>? assetFiles = null,
        IReadOnlyDictionary<string, string>? licenseFiles = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            return await Task.Run(
                () => SaveCore(manifest, assetFiles, licenseFiles, cancellationToken),
                cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<SoundPackDescriptor> SaveImportedAsync(
        SoundPackManifest manifest,
        IReadOnlyDictionary<SoundPackAssetId, string> assetFiles,
        IReadOnlyDictionary<string, string> licenseFiles,
        SoundPackImportCollisionPolicy collisionPolicy,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            return await Task.Run(
                () =>
                {
                    EnsureRoot();
                    var resolvedManifest = manifest;
                    if (Directory.Exists(PackPath(resolvedManifest.Id)))
                    {
                        switch (collisionPolicy)
                        {
                            case SoundPackImportCollisionPolicy.Duplicate:
                                Guid nextId;
                                do
                                {
                                    nextId = Guid.NewGuid();
                                }
                                while (Directory.Exists(PackPath(nextId)));

                                var now = DateTimeOffset.UtcNow;
                                resolvedManifest = resolvedManifest with
                                {
                                    Id = nextId,
                                    CreatedAt = now,
                                    ModifiedAt = now,
                                };
                                break;
                            case SoundPackImportCollisionPolicy.Replace:
                                break;
                            case SoundPackImportCollisionPolicy.Reject:
                                throw new SoundPackException(
                                    SoundPackErrorKind.PackAlreadyExists,
                                    $"Sound pack {resolvedManifest.Id:D} already exists.");
                            default:
                                throw new ArgumentOutOfRangeException(nameof(collisionPolicy));
                        }
                    }

                    return SaveCore(
                        resolvedManifest,
                        assetFiles,
                        licenseFiles,
                        cancellationToken);
                },
                cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<string> RemoveAsync(
        Guid id,
        CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            return await Task.Run(
                () =>
                {
                    EnsureRoot();
                    var source = PackPath(id);
                    if (!Directory.Exists(source))
                    {
                        throw new SoundPackException(
                            SoundPackErrorKind.PackNotFound,
                            $"Sound pack {id:D} was not found.");
                    }

                    _ = _packageValidator.Validate(source);
                    var trash = Path.Combine(RootPath, ".Trash");
                    DiySoundPackFileSafety.EnsureSafeDirectory(trash, create: true);
                    var destination = Path.Combine(
                        trash,
                        $"{id:D}-{Guid.NewGuid():N}.simuboardpack".ToLowerInvariant());
                    Directory.Move(source, destination);
                    return destination;
                },
                cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    private SoundPackDescriptor[] DescriptorsCore(CancellationToken cancellationToken)
    {
        EnsureRoot();
        var bundled = LoadBundledPacks();
        var bundledIds = bundled.Keys.ToHashSet();
        var custom = new List<SoundPackDescriptor>();
        foreach (var directory in Directory.EnumerateDirectories(RootPath, "*.simuboardpack"))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var name = Path.GetFileNameWithoutExtension(directory);
            if (!Guid.TryParse(name, out var id))
            {
                continue;
            }

            if (bundledIds.Contains(id))
            {
                // Once the app ships the same UUID as a read-only bundled pack,
                // keep any old local package on disk but hide the duplicate row.
                continue;
            }

            try
            {
                custom.Add(LoadCore(id).Descriptor);
            }
            catch (Exception error) when (
                error is SoundPackException or IOException or UnauthorizedAccessException)
            {
                // One corrupt package must not hide the rest of the library.
            }
        }

        custom.Sort((left, right) =>
            StringComparer.CurrentCultureIgnoreCase.Compare(left.Name, right.Name));
        var bundledDescriptors = bundled.Values
            .Select(document => document.Descriptor)
            .OrderBy(descriptor => descriptor.Name, StringComparer.CurrentCultureIgnoreCase);
        return _builtInDescriptors.Concat(bundledDescriptors).Concat(custom).ToArray();
    }

    private DiySoundPackDocument LoadCore(Guid id)
    {
        EnsureRoot();
        if (TryLoadBundledPack(id, out var bundled))
        {
            return bundled;
        }

        var path = PackPath(id);
        if (!Directory.Exists(path))
        {
            throw new SoundPackException(
                SoundPackErrorKind.PackNotFound,
                $"Sound pack {id:D} was not found.");
        }

        var package = _packageValidator.Validate(path);
        if (package.Manifest.Id != id)
        {
            throw new SoundPackException(
                SoundPackErrorKind.InvalidManifest,
                "The installed directory ID does not match manifest.id.");
        }

        return new DiySoundPackDocument(
            SoundPackDescriptors.Custom(package.Manifest),
            package.Manifest,
            package.RootPath);
    }

    private SoundPackDescriptor SaveCore(
        SoundPackManifest sourceManifest,
        IReadOnlyDictionary<SoundPackAssetId, string>? suppliedAssetFiles,
        IReadOnlyDictionary<string, string>? suppliedLicenseFiles,
        CancellationToken cancellationToken)
    {
        EnsureRoot();
        var manifest = sourceManifest with { ModifiedAt = DateTimeOffset.UtcNow };
        SoundPackValidator.Validate(manifest, _limits);

        var destination = PackPath(manifest.Id);
        ValidatedDiySoundPack? previous = null;
        if (Directory.Exists(destination))
        {
            previous = _packageValidator.Validate(destination);
            if (previous.Manifest.Id != manifest.Id)
            {
                throw new SoundPackException(
                    SoundPackErrorKind.InvalidManifest,
                    "The existing package ID does not match its directory name.");
            }
        }

        var staging = Path.Combine(
            RootPath,
            $".staging-{manifest.Id:D}-{Guid.NewGuid():N}.simuboardpack".ToLowerInvariant());
        Directory.CreateDirectory(staging);
        try
        {
            var assetsDirectory = Path.Combine(staging, "assets");
            Directory.CreateDirectory(assetsDirectory);
            foreach (var asset in manifest.Assets.Values.OrderBy(asset => asset.Id.Value, StringComparer.Ordinal))
            {
                cancellationToken.ThrowIfCancellationRequested();
                string sourcePath;
                if (suppliedAssetFiles is not null &&
                    suppliedAssetFiles.TryGetValue(asset.Id, out var supplied))
                {
                    sourcePath = supplied;
                }
                else if (previous is not null &&
                    previous.AssetFiles.TryGetValue(asset.Id, out var existing))
                {
                    sourcePath = existing;
                }
                else
                {
                    throw new SoundPackException(
                        SoundPackErrorKind.MissingAsset,
                        $"Missing asset file {asset.Id.Value}.");
                }

                var audioLimits = new DiyAudioImportLimits(
                    MaximumSourceBytes: _limits.MaximumAssetBytes,
                    MinimumDurationSeconds: _limits.MinimumAudioDurationSeconds,
                    MaximumDurationSeconds: _limits.MaximumAudioDurationSeconds);
                var info = Pcm16WaveFile.ValidateNormalized(sourcePath, audioLimits);
                var hash = Pcm16WaveFile.Sha256(sourcePath, _limits.MaximumAssetBytes);
                if (!string.Equals(hash, asset.Sha256, StringComparison.Ordinal) ||
                    info.ByteCount != asset.ByteCount ||
                    Math.Abs(info.DurationSeconds - asset.DurationSeconds) >= 0.002)
                {
                    throw new SoundPackException(
                        SoundPackErrorKind.HashMismatch,
                        $"Asset metadata or hash does not match {asset.RelativePath}.");
                }

                var target = DiySoundPackFileSafety.DescendantPath(staging, asset.RelativePath);
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                DiySoundPackFileSafety.CopyRegularFile(
                    sourcePath,
                    target,
                    _limits.MaximumAssetBytes);
            }

            var licenses = suppliedLicenseFiles is { Count: > 0 }
                ? suppliedLicenseFiles
                : previous?.LicenseFiles;
            if (licenses is not null)
            {
                foreach (var (relativeName, sourcePath) in licenses)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    var logicalPath = $"licenses/{relativeName}";
                    DiySoundPackFileSafety.ValidateLogicalRelativePath(logicalPath);
                    _ = DiySoundPackFileSafety.ValidateRegularFile(sourcePath, _limits.MaximumAssetBytes);
                    var target = DiySoundPackFileSafety.DescendantPath(staging, logicalPath);
                    Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                    DiySoundPackFileSafety.CopyRegularFile(
                        sourcePath,
                        target,
                        _limits.MaximumAssetBytes);
                }
            }

            var manifestData = SoundPackManifestJson.Encode(manifest);
            if (manifestData.LongLength > _limits.MaximumManifestBytes)
            {
                throw new SoundPackException(
                    SoundPackErrorKind.SizeLimitExceeded,
                    "manifest.json is too large.");
            }

            File.WriteAllBytes(Path.Combine(staging, "manifest.json"), manifestData);
            _ = _packageValidator.Validate(staging);
            DiySoundPackDirectoryTransaction.Install(
                staging,
                destination,
                RootPath,
                replaceExisting: previous is not null);
            return SoundPackDescriptors.Custom(manifest);
        }
        finally
        {
            if (Directory.Exists(staging))
            {
                DiySoundPackFileSafety.DeleteOwnedDirectory(RootPath, staging, ".staging-");
            }
        }
    }

    private void EnsureRoot() =>
        DiySoundPackFileSafety.EnsureSafeDirectory(RootPath, create: true);

    private Dictionary<Guid, DiySoundPackDocument> LoadBundledPacks()
    {
        if (string.IsNullOrWhiteSpace(_bundledPackRootPath) ||
            !Directory.Exists(_bundledPackRootPath))
        {
            return [];
        }

        DiySoundPackFileSafety.EnsureSafeDirectory(_bundledPackRootPath, create: false);
        var bundled = new Dictionary<Guid, DiySoundPackDocument>();
        foreach (var directory in Directory.EnumerateDirectories(_bundledPackRootPath, "*.simuboardpack"))
        {
            var name = Path.GetFileNameWithoutExtension(directory);
            if (!Guid.TryParse(name, out var id))
            {
                continue;
            }

            try
            {
                var package = _packageValidator.Validate(directory);
                if (package.Manifest.Id != id)
                {
                    continue;
                }

                bundled[id] = new DiySoundPackDocument(
                    SoundPackDescriptors.BundledPack(package.Manifest),
                    package.Manifest,
                    package.RootPath);
            }
            catch (Exception error) when (
                error is SoundPackException or IOException or UnauthorizedAccessException)
            {
                // One damaged bundled package must not hide the remaining
                // packaged content. Release validation checks the shipped pack.
            }
        }

        return bundled;
    }

    private bool TryLoadBundledPack(Guid id, out DiySoundPackDocument document)
    {
        document = null!;
        var bundled = LoadBundledPacks();
        return bundled.TryGetValue(id, out document!);
    }

    private static string DefaultRootPath() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Battuta",
        "SoundPacks");

    private static string DefaultBundledPackRootPath() =>
        Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "BundledSoundPacks"));

    public void Dispose()
    {
        _gate.Dispose();
        GC.SuppressFinalize(this);
    }
}
