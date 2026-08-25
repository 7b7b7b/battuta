using System.IO;
using Battuta.Windows.Startup;

namespace Battuta.Windows.Tests.Platform.Startup;

public sealed class RegistryLaunchAtLoginServiceTests
{
    [Fact]
    public async Task EnableAndDisableOnlyOwnExactEntry()
    {
        using var directory = new TestDirectory();
        var executable = Path.Combine(directory.Path, "Battuta.exe");
        await File.WriteAllBytesAsync(executable, [0]);
        var store = new MemoryStartupEntryStore();
        var service = new RegistryLaunchAtLoginService(
            executable,
            store,
            isDevelopmentBuild: false);

        var enabled = await service.SetEnabledAsync(true);

        Assert.Equal(LaunchAtLoginStatus.Enabled, enabled.Status);
        Assert.Equal(service.ExpectedCommandLine, store.Value);

        var disabled = await service.SetEnabledAsync(false);

        Assert.Equal(LaunchAtLoginStatus.Disabled, disabled.Status);
        Assert.Null(store.Value);
    }

    [Fact]
    public async Task DisablePreservesEntryOwnedByDifferentPath()
    {
        using var directory = new TestDirectory();
        var executable = Path.Combine(directory.Path, "Battuta.exe");
        await File.WriteAllBytesAsync(executable, [0]);
        var store = new MemoryStartupEntryStore
        {
            Value = "\"C:\\Other\\Battuta.exe\" --startup",
        };
        var service = new RegistryLaunchAtLoginService(
            executable,
            store,
            isDevelopmentBuild: false);

        var state = await service.SetEnabledAsync(false);

        Assert.Equal(LaunchAtLoginStatus.Failed, state.Status);
        Assert.Equal("\"C:\\Other\\Battuta.exe\" --startup", store.Value);
    }

    private sealed class MemoryStartupEntryStore : IStartupEntryStore
    {
        public string? Value { get; set; }

        public string? Read(string valueName) => Value;

        public void Write(string valueName, string commandLine) => Value = commandLine;

        public void Delete(string valueName) => Value = null;
    }
}
