using System.IO;
using Battuta.Windows.Settings;

namespace Battuta.Windows.Tests.Platform.Settings;

public sealed class JsonAppSettingsStoreTests
{
    [Fact]
    public async Task MissingFileReturnsMacCompatibleDefaults()
    {
        using var directory = new TestDirectory();
        using var store = new JsonAppSettingsStore(Path.Combine(directory.Path, "settings.json"));

        var settings = await store.LoadAsync();

        Assert.True(settings.IsEnabled);
        Assert.Equal("holypanda", settings.SelectedProfileId);
        Assert.Equal(0.42, settings.Volume, precision: 6);
        Assert.Equal(0.273, settings.PointerVolume, precision: 6);
        Assert.True(settings.PlaysReleaseSound);
        Assert.True(settings.UsesPitchVariation);
        Assert.False(settings.IsPointerSoundEnabled);
        Assert.False(settings.IsTypingStatsEnabled);
        Assert.True(settings.IsLaunchAtLoginEnabled);
        Assert.Equal(AutomaticUpdateCheckPreference.Undecided, settings.AutomaticUpdateCheckPreference);
    }

    [Fact]
    public async Task LegacyFileDerivesPointerVolumeFromStoredKeyboardVolume()
    {
        using var directory = new TestDirectory();
        var path = Path.Combine(directory.Path, "settings.json");
        await File.WriteAllTextAsync(path, """
            {
              "schemaVersion": 1,
              "volume": 0.8,
              "selectedProfileId": "mxbrown"
            }
            """);
        using var store = new JsonAppSettingsStore(path);

        var settings = await store.LoadAsync();

        Assert.Equal(0.8, settings.Volume, precision: 6);
        Assert.Equal(0.52, settings.PointerVolume, precision: 6);
        Assert.Equal("mxbrown", settings.SelectedProfileId);
    }

    [Fact]
    public async Task SaveNormalizesAndRoundTripsValues()
    {
        using var directory = new TestDirectory();
        var path = Path.Combine(directory.Path, "settings.json");
        using var store = new JsonAppSettingsStore(path);
        var source = new AppSettingsSnapshot
        {
            Volume = 4,
            PointerVolume = double.NaN,
            SelectedProfileId = "unknown",
            SelectedPointerProfileId = "GLASS",
            AutomaticUpdateCheckPreference = AutomaticUpdateCheckPreference.Enabled,
        };

        await store.SaveAsync(source);
        var loaded = await store.LoadAsync();

        Assert.Equal(1, loaded.Volume);
        Assert.Equal(0.65, loaded.PointerVolume, precision: 6);
        Assert.Equal("holypanda", loaded.SelectedProfileId);
        Assert.Equal("glass", loaded.SelectedPointerProfileId);
        Assert.Equal(AutomaticUpdateCheckPreference.Enabled, loaded.AutomaticUpdateCheckPreference);
    }

    [Fact]
    public async Task CorruptPrimaryIsPreservedAndBackupIsRecovered()
    {
        using var directory = new TestDirectory();
        var path = Path.Combine(directory.Path, "settings.json");
        var backup = path + ".bak";
        await File.WriteAllTextAsync(path, "{not-json");
        await File.WriteAllTextAsync(backup, """
            { "selectedProfileId": "topre", "volume": 0.3 }
            """);
        using var store = new JsonAppSettingsStore(path, backup);

        var loaded = await store.LoadAsync();

        Assert.Equal("topre", loaded.SelectedProfileId);
        Assert.Single(Directory.GetFiles(directory.Path, "settings.corrupt-*.json"));
    }
}
