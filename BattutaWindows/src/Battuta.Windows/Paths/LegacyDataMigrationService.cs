using System.IO;

namespace Battuta.Windows.Paths;

/// <summary>
/// Imports known user data once when a user moves from an unpackaged build to
/// MSIX. Existing destination files always win.
/// </summary>
public sealed class LegacyDataMigrationService(AppPaths paths)
{
    private const string MarkerName = ".legacy-unpackaged-data-imported-v1";
    private readonly AppPaths _paths = paths ?? throw new ArgumentNullException(nameof(paths));

    public async Task<bool> ImportIfNeededAsync(CancellationToken cancellationToken = default)
    {
        if (!_paths.IsPackaged || string.IsNullOrWhiteSpace(_paths.LegacyUnpackagedDataRoot))
        {
            return false;
        }

        var sourceRoot = _paths.LegacyUnpackagedDataRoot;
        var marker = Path.Combine(_paths.DataRoot, MarkerName);
        if (!Directory.Exists(sourceRoot) || File.Exists(marker))
        {
            return false;
        }

        _paths.EnsureCreated();
        var imported = false;
        imported |= await CopyFileIfMissingAsync(
            Path.Combine(sourceRoot, "settings.json"),
            _paths.SettingsFile,
            cancellationToken);
        imported |= await CopyFileIfMissingAsync(
            Path.Combine(sourceRoot, "typing-stats.sqlite3"),
            _paths.StatisticsDatabaseFile,
            cancellationToken);

        imported |= await CopyDirectoryIfMissingAsync(
            Path.Combine(sourceRoot, "SoundPacks"),
            _paths.SoundPacksDirectory,
            cancellationToken);

        await File.WriteAllTextAsync(marker, DateTimeOffset.UtcNow.ToString("O"), cancellationToken);
        return imported;
    }

    private static async Task<bool> CopyFileIfMissingAsync(
        string source,
        string destination,
        CancellationToken cancellationToken)
    {
        if (!File.Exists(source) || File.Exists(destination))
        {
            return false;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        await using var input = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.Read);
        await using var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        await input.CopyToAsync(output, cancellationToken);
        await output.FlushAsync(cancellationToken);
        return true;
    }

    private static async Task<bool> CopyDirectoryIfMissingAsync(
        string sourceDirectory,
        string destinationDirectory,
        CancellationToken cancellationToken)
    {
        if (!Directory.Exists(sourceDirectory))
        {
            return false;
        }

        var imported = false;
        foreach (var sourceFile in Directory.EnumerateFiles(sourceDirectory, "*", SearchOption.AllDirectories))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var relative = Path.GetRelativePath(sourceDirectory, sourceFile);
            if (relative.StartsWith("..", StringComparison.Ordinal)
                || Path.IsPathRooted(relative))
            {
                continue;
            }

            var destination = Path.Combine(destinationDirectory, relative);
            imported |= await CopyFileIfMissingAsync(sourceFile, destination, cancellationToken);
        }

        return imported;
    }
}
