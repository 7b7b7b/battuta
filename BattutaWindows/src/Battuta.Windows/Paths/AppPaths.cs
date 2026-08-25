using Battuta.Windows.Platform;
using System.IO;

namespace Battuta.Windows.Paths;

/// <summary>
/// All mutable Battuta data lives outside the application directory so an
/// update never replaces settings, statistics, DIY packs, or logs.
/// </summary>
public sealed class AppPaths
{
    public const string ProductDirectoryName = "Battuta";

    public AppPaths(string dataRoot, bool isPackaged = false, string? legacyDataRoot = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(dataRoot);

        DataRoot = Path.GetFullPath(dataRoot);
        IsPackaged = isPackaged;
        LegacyUnpackagedDataRoot = legacyDataRoot is null ? null : Path.GetFullPath(legacyDataRoot);
    }

    public string DataRoot { get; }

    public bool IsPackaged { get; }

    public string? LegacyUnpackagedDataRoot { get; }

    public string SettingsFile => Path.Combine(DataRoot, "settings.json");

    public string SettingsBackupFile => Path.Combine(DataRoot, "settings.json.bak");

    public string UpdateCacheFile => Path.Combine(DataRoot, "update-cache.json");

    public string StatisticsDatabaseFile => Path.Combine(DataRoot, "typing-stats.sqlite3");

    public string SoundPacksDirectory => Path.Combine(DataRoot, "SoundPacks");

    public string LogsDirectory => Path.Combine(DataRoot, "Logs");

    public string TemporaryDirectory => Path.Combine(DataRoot, "Temp");

    public static AppPaths ForCurrentProcess(
        PackageIdentityInfo? identity = null,
        string? localApplicationData = null)
    {
        identity ??= PackageIdentityDetector.GetCurrent();
        localApplicationData ??= Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrWhiteSpace(localApplicationData))
        {
            throw new InvalidOperationException("Windows local application data directory is unavailable.");
        }

        var unpackagedRoot = Path.Combine(localApplicationData, ProductDirectoryName);
        if (!identity.IsPackaged || string.IsNullOrWhiteSpace(identity.FamilyName))
        {
            return new AppPaths(unpackagedRoot);
        }

        var packagedRoot = Path.Combine(
            localApplicationData,
            "Packages",
            identity.FamilyName,
            "LocalState");
        return new AppPaths(packagedRoot, isPackaged: true, legacyDataRoot: unpackagedRoot);
    }

    public void EnsureCreated()
    {
        Directory.CreateDirectory(DataRoot);
        Directory.CreateDirectory(SoundPacksDirectory);
        Directory.CreateDirectory(LogsDirectory);
        Directory.CreateDirectory(TemporaryDirectory);
    }
}
