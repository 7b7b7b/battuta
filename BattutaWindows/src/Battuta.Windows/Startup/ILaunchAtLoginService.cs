namespace Battuta.Windows.Startup;

public enum LaunchAtLoginStatus
{
    Disabled,
    Enabled,
    DisabledByUser,
    DisabledByPolicy,
    NeedsStableApplicationPath,
    Unavailable,
    Failed,
}

public sealed record LaunchAtLoginState(
    LaunchAtLoginStatus Status,
    string Description,
    bool CanChangeInApplication,
    bool CanOpenSystemSettings = true);

public interface ILaunchAtLoginService
{
    Task<LaunchAtLoginState> GetStateAsync(CancellationToken cancellationToken = default);

    Task<LaunchAtLoginState> SetEnabledAsync(
        bool enabled,
        CancellationToken cancellationToken = default);

    bool OpenSystemSettings();
}
