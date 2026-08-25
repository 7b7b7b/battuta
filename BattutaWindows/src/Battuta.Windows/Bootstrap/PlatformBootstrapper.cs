using Battuta.Windows.Activation;
using Battuta.Windows.Paths;
using Battuta.Windows.Settings;
using Battuta.Windows.Startup;

namespace Battuta.Windows.Bootstrap;

public sealed class PlatformBootstrapResult : IAsyncDisposable
{
    internal PlatformBootstrapResult(
        bool isPrimary,
        bool activationDelivered,
        ActivationRequest activation,
        SingleInstanceService? singleInstance,
        AppPaths? paths,
        JsonAppSettingsStore? settingsStore,
        SettingsAutosaveService? settingsAutosave,
        AppSettingsSnapshot? settings,
        ILaunchAtLoginService? launchAtLogin,
        LaunchAtLoginState? launchAtLoginState)
    {
        IsPrimary = isPrimary;
        ActivationDelivered = activationDelivered;
        Activation = activation;
        SingleInstance = singleInstance;
        Paths = paths;
        SettingsStore = settingsStore;
        SettingsAutosave = settingsAutosave;
        Settings = settings;
        LaunchAtLogin = launchAtLogin;
        LaunchAtLoginState = launchAtLoginState;
    }

    public bool IsPrimary { get; }

    public bool ActivationDelivered { get; }

    public ActivationRequest Activation { get; }

    public SingleInstanceService? SingleInstance { get; }

    public AppPaths? Paths { get; }

    public JsonAppSettingsStore? SettingsStore { get; }

    public SettingsAutosaveService? SettingsAutosave { get; }

    public AppSettingsSnapshot? Settings { get; }

    public ILaunchAtLoginService? LaunchAtLogin { get; }

    public LaunchAtLoginState? LaunchAtLoginState { get; }

    public async ValueTask DisposeAsync()
    {
        if (SettingsAutosave is not null)
        {
            await SettingsAutosave.DisposeAsync();
        }

        SettingsStore?.Dispose();
        if (SingleInstance is not null)
        {
            await SingleInstance.DisposeAsync();
        }
    }
}

/// <summary>
/// Performs the platform-only part of startup before hooks and audio begin.
/// App.xaml.cs can consume this result without duplicating path, settings,
/// single-instance, or startup-entry policy.
/// </summary>
public static class PlatformBootstrapper
{
    public static async Task<PlatformBootstrapResult> StartAsync(
        IEnumerable<string> arguments,
        SynchronizationContext? callbackContext = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(arguments);
        var activation = ActivationRequest.FromArguments(arguments, Environment.CurrentDirectory);
        var acquisition = await SingleInstanceService.AcquireAsync(
            activation,
            callbackContext: callbackContext,
            cancellationToken: cancellationToken).ConfigureAwait(false);
        if (!acquisition.IsPrimary)
        {
            return new PlatformBootstrapResult(
                isPrimary: false,
                acquisition.ActivationDelivered,
                activation,
                singleInstance: null,
                paths: null,
                settingsStore: null,
                settingsAutosave: null,
                settings: null,
                launchAtLogin: null,
                launchAtLoginState: null);
        }

        var singleInstance = acquisition.PrimaryInstance!;
        JsonAppSettingsStore? settingsStore = null;
        SettingsAutosaveService? autosave = null;
        try
        {
            var paths = AppPaths.ForCurrentProcess();
            paths.EnsureCreated();
            _ = await new LegacyDataMigrationService(paths)
                .ImportIfNeededAsync(cancellationToken)
                .ConfigureAwait(false);

            settingsStore = new JsonAppSettingsStore(paths);
            var settings = await settingsStore.LoadAsync(cancellationToken).ConfigureAwait(false);
            autosave = new SettingsAutosaveService(settingsStore);
            var executablePath = Environment.ProcessPath
                ?? throw new InvalidOperationException("The Battuta executable path is unavailable.");
            var launchAtLogin = LaunchAtLoginServiceFactory.Create(executablePath);
            var launchState = await launchAtLogin.SetEnabledAsync(
                settings.IsLaunchAtLoginEnabled,
                cancellationToken).ConfigureAwait(false);

            return new PlatformBootstrapResult(
                isPrimary: true,
                activationDelivered: false,
                activation,
                singleInstance,
                paths,
                settingsStore,
                autosave,
                settings,
                launchAtLogin,
                launchState);
        }
        catch
        {
            if (autosave is not null)
            {
                await autosave.DisposeAsync();
            }

            settingsStore?.Dispose();
            await singleInstance.DisposeAsync();
            throw;
        }
    }
}
