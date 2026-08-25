using Battuta.Windows.Paths;
using Battuta.Windows.Settings;

namespace Battuta.Windows.Tests.Runtime;

public sealed class CustomSoundPackSettingsTests
{
    [Fact]
    public async Task CustomSelectionRoundTripsThroughDurableSettings()
    {
        var root = Path.Combine(Path.GetTempPath(), $"battuta-custom-settings-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        try
        {
            var selection = $"custom:{Guid.NewGuid():D}".ToLowerInvariant();
            var paths = new AppPaths(root);
            using var store = new JsonAppSettingsStore(paths);

            await store.SaveAsync(new AppSettingsSnapshot { SelectedProfileId = selection });
            var reloaded = await store.LoadAsync();

            Assert.Equal(selection, reloaded.SelectedProfileId);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }
}
