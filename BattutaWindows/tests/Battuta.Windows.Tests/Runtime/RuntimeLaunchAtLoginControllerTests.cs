using Battuta.Windows.Runtime;
using Battuta.Windows.Startup;

namespace Battuta.Windows.Tests.Runtime;

public sealed class RuntimeLaunchAtLoginControllerTests
{
    [Fact]
    public void InitialPlatformBootstrapStateIsPublishedImmediately()
    {
        var initial = State(LaunchAtLoginStatus.Enabled, "Enabled");
        var controller = new RuntimeLaunchAtLoginController(null, initial);

        Assert.Same(initial, controller.State);
    }

    [Fact]
    public async Task SetEnabledPublishesTheServiceReturnValue()
    {
        var returned = State(
            LaunchAtLoginStatus.DisabledByUser,
            "Change this in Windows settings",
            canChange: false);
        var service = new FakeLaunchAtLoginService { SetResult = returned };
        var controller = new RuntimeLaunchAtLoginController(
            service,
            State(LaunchAtLoginStatus.Disabled, "Disabled"));
        var changes = 0;
        controller.StateChanged += (_, _) => changes++;

        var actual = await controller.SetEnabledAsync(enabled: true);

        Assert.Same(returned, actual);
        Assert.Same(returned, controller.State);
        Assert.True(service.LastRequestedEnabled);
        Assert.Equal(1, changes);
    }

    [Fact]
    public async Task RefreshPublishesOnlyAnEffectiveStateChange()
    {
        var initial = State(LaunchAtLoginStatus.Disabled, "Disabled");
        var service = new FakeLaunchAtLoginService { GetResult = initial };
        var controller = new RuntimeLaunchAtLoginController(service, initial);
        var changes = 0;
        controller.StateChanged += (_, _) => changes++;

        _ = await controller.RefreshAsync();
        service.GetResult = State(LaunchAtLoginStatus.Enabled, "Enabled");
        var refreshed = await controller.RefreshAsync();

        Assert.Equal(LaunchAtLoginStatus.Enabled, refreshed?.Status);
        Assert.Equal(1, changes);
        Assert.Equal(2, service.GetStateCallCount);
    }

    [Fact]
    public void OpenSystemSettingsHonorsCapabilityAndForwardsWhenAvailable()
    {
        var blockedService = new FakeLaunchAtLoginService { OpenResult = true };
        var blocked = new RuntimeLaunchAtLoginController(
            blockedService,
            new LaunchAtLoginState(
                LaunchAtLoginStatus.DisabledByPolicy,
                "Blocked",
                CanChangeInApplication: false,
                CanOpenSystemSettings: false));
        Assert.False(blocked.OpenSystemSettings());
        Assert.Equal(0, blockedService.OpenCallCount);

        var availableService = new FakeLaunchAtLoginService { OpenResult = true };
        var available = new RuntimeLaunchAtLoginController(
            availableService,
            State(LaunchAtLoginStatus.DisabledByUser, "Open Windows", canChange: false));
        Assert.True(available.OpenSystemSettings());
        Assert.Equal(1, availableService.OpenCallCount);
    }

    private static LaunchAtLoginState State(
        LaunchAtLoginStatus status,
        string description,
        bool canChange = true) =>
        new(status, description, canChange);

    private sealed class FakeLaunchAtLoginService : ILaunchAtLoginService
    {
        public LaunchAtLoginState GetResult { get; set; } =
            State(LaunchAtLoginStatus.Disabled, "Disabled");

        public LaunchAtLoginState SetResult { get; set; } =
            State(LaunchAtLoginStatus.Enabled, "Enabled");

        public bool OpenResult { get; set; }

        public bool LastRequestedEnabled { get; private set; }

        public int GetStateCallCount { get; private set; }

        public int OpenCallCount { get; private set; }

        public Task<LaunchAtLoginState> GetStateAsync(CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            GetStateCallCount++;
            return Task.FromResult(GetResult);
        }

        public Task<LaunchAtLoginState> SetEnabledAsync(
            bool enabled,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            LastRequestedEnabled = enabled;
            return Task.FromResult(SetResult);
        }

        public bool OpenSystemSettings()
        {
            OpenCallCount++;
            return OpenResult;
        }
    }
}
