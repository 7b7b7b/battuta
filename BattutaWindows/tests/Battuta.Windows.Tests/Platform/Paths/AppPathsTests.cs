using System.IO;
using Battuta.Windows.Paths;
using Battuta.Windows.Platform;

namespace Battuta.Windows.Tests.Platform.Paths;

public sealed class AppPathsTests
{
    [Fact]
    public void UnpackagedBuildUsesStableLocalApplicationDataRoot()
    {
        using var directory = new TestDirectory();
        var paths = AppPaths.ForCurrentProcess(PackageIdentityInfo.Unpackaged, directory.Path);

        Assert.False(paths.IsPackaged);
        Assert.Equal(
            Path.Combine(directory.Path, AppPaths.ProductDirectoryName),
            paths.DataRoot);
        Assert.EndsWith("settings.json", paths.SettingsFile, StringComparison.Ordinal);
        Assert.EndsWith("typing-stats.sqlite3", paths.StatisticsDatabaseFile, StringComparison.Ordinal);
    }

    [Fact]
    public void PackagedBuildUsesPackageLocalStateAndKeepsLegacyImportRoot()
    {
        using var directory = new TestDirectory();
        var identity = new PackageIdentityInfo(
            true,
            "Wormforce.Battuta_1.1.0.0_x64__publisher",
            "Wormforce.Battuta_publisher");

        var paths = AppPaths.ForCurrentProcess(identity, directory.Path);

        Assert.True(paths.IsPackaged);
        Assert.Equal(
            Path.Combine(
                directory.Path,
                "Packages",
                identity.FamilyName!,
                "LocalState"),
            paths.DataRoot);
        Assert.Equal(
            Path.Combine(directory.Path, AppPaths.ProductDirectoryName),
            paths.LegacyUnpackagedDataRoot);
    }

    [Fact]
    public void EnsureCreatedCreatesOnlyKnownMutableDirectories()
    {
        using var directory = new TestDirectory();
        var paths = new AppPaths(Path.Combine(directory.Path, "data"));

        paths.EnsureCreated();

        Assert.True(Directory.Exists(paths.DataRoot));
        Assert.True(Directory.Exists(paths.SoundPacksDirectory));
        Assert.True(Directory.Exists(paths.LogsDirectory));
        Assert.True(Directory.Exists(paths.TemporaryDirectory));
    }
}
