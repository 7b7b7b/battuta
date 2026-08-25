using System.Diagnostics;

#if WINDOWS10_0_17763_0_OR_GREATER
using Windows.ApplicationModel;
#endif

namespace Battuta.Windows.Startup;

/// <summary>
/// MSIX StartupTask adapter. The fallback branch keeps an unpackaged or
/// unversioned Windows TFM build compilable while the manifest template is
/// still being wired into the packaging project.
/// </summary>
public sealed class PackagedLaunchAtLoginService(
    string taskId = PackagedLaunchAtLoginService.DefaultTaskId) : ILaunchAtLoginService
{
    public const string DefaultTaskId = "BattutaStartup";
    private readonly string _taskId = taskId;

    public async Task<LaunchAtLoginState> GetStateAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
#if WINDOWS10_0_17763_0_OR_GREATER
        try
        {
            var task = await StartupTask.GetAsync(_taskId);
            return MapState(task.State);
        }
        catch (Exception exception)
        {
            return Failed(exception);
        }
#else
        await Task.CompletedTask;
        return Unavailable();
#endif
    }

    public async Task<LaunchAtLoginState> SetEnabledAsync(
        bool enabled,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
#if WINDOWS10_0_17763_0_OR_GREATER
        try
        {
            var task = await StartupTask.GetAsync(_taskId);
            if (!enabled)
            {
                task.Disable();
                return MapState(task.State);
            }

            if (task.State == StartupTaskState.Disabled)
            {
                return MapState(await task.RequestEnableAsync());
            }

            return MapState(task.State);
        }
        catch (Exception exception)
        {
            return Failed(exception);
        }
#else
        await Task.CompletedTask;
        return Unavailable();
#endif
    }

    public bool OpenSystemSettings()
    {
        try
        {
            Process.Start(new ProcessStartInfo("ms-settings:startupapps")
            {
                UseShellExecute = true,
            });
            return true;
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            return false;
        }
    }

#if WINDOWS10_0_17763_0_OR_GREATER
    private static LaunchAtLoginState MapState(StartupTaskState state) => state switch
    {
        StartupTaskState.Enabled => new(
            LaunchAtLoginStatus.Enabled,
            "已加入 Windows 启动应用，下次登录会自动启动。",
            CanChangeInApplication: true),
        StartupTaskState.Disabled => new(
            LaunchAtLoginStatus.Disabled,
            "已关闭；重新登录后不会自动启动。",
            CanChangeInApplication: true),
        StartupTaskState.DisabledByUser => new(
            LaunchAtLoginStatus.DisabledByUser,
            "已由用户在 Windows 启动应用设置中关闭，必须在那里重新允许。",
            CanChangeInApplication: false),
        StartupTaskState.DisabledByPolicy => new(
            LaunchAtLoginStatus.DisabledByPolicy,
            "登录启动已被系统策略关闭。",
            CanChangeInApplication: false),
        _ => Unavailable(),
    };
#endif

    private static LaunchAtLoginState Unavailable() => new(
        LaunchAtLoginStatus.Unavailable,
        "当前构建没有可用的 MSIX StartupTask。",
        CanChangeInApplication: false);

    private static LaunchAtLoginState Failed(Exception exception) => new(
        LaunchAtLoginStatus.Failed,
        $"无法读取 Windows 启动任务：{exception.Message}",
        CanChangeInApplication: true);
}
