using System.Diagnostics;
using System.IO;
using System.Security;

namespace Battuta.Windows.Startup;

/// <summary>
/// Current-user startup registration for unpackaged builds. It only removes a
/// value that still points to this exact executable.
/// </summary>
public sealed class RegistryLaunchAtLoginService : ILaunchAtLoginService
{
    public const string DefaultValueName = "Battuta";
    private readonly IStartupEntryStore _store;
    private readonly string _executablePath;
    private readonly string _valueName;
    private readonly bool _isDevelopmentBuild;

    public RegistryLaunchAtLoginService(
        string executablePath,
        IStartupEntryStore? store = null,
        string valueName = DefaultValueName,
        bool? isDevelopmentBuild = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(executablePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(valueName);
        _executablePath = Path.GetFullPath(executablePath);
        _store = store ?? new RegistryStartupEntryStore();
        _valueName = valueName;
        _isDevelopmentBuild = isDevelopmentBuild ?? IsDevelopmentPath(_executablePath);
    }

    public Task<LaunchAtLoginState> GetStateAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (_isDevelopmentBuild || !File.Exists(_executablePath))
        {
            return Task.FromResult(NeedsStablePathState());
        }

        try
        {
            var stored = _store.Read(_valueName);
            if (stored is null)
            {
                return Task.FromResult(DisabledState());
            }

            return Task.FromResult(CommandLinesEqual(stored, ExpectedCommandLine)
                ? EnabledState()
                : new LaunchAtLoginState(
                    LaunchAtLoginStatus.Failed,
                    "启动项名称已被其他路径占用；为避免误删，Battuta 没有改动它。",
                    CanChangeInApplication: false));
        }
        catch (Exception exception) when (exception is UnauthorizedAccessException or IOException or SecurityException)
        {
            return Task.FromResult(FailedState(exception));
        }
    }

    public async Task<LaunchAtLoginState> SetEnabledAsync(
        bool enabled,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (_isDevelopmentBuild || !File.Exists(_executablePath))
        {
            return NeedsStablePathState();
        }

        try
        {
            var existing = _store.Read(_valueName);
            if (enabled)
            {
                if (existing is not null && !CommandLinesEqual(existing, ExpectedCommandLine))
                {
                    return new LaunchAtLoginState(
                        LaunchAtLoginStatus.Failed,
                        "启动项名称已被其他 Battuta 路径占用，请先在 Windows 启动应用设置中处理。",
                        CanChangeInApplication: false);
                }

                _store.Write(_valueName, ExpectedCommandLine);
            }
            else if (existing is not null)
            {
                if (!CommandLinesEqual(existing, ExpectedCommandLine))
                {
                    return new LaunchAtLoginState(
                        LaunchAtLoginStatus.Failed,
                        "现有启动项不属于当前 Battuta，已保留原值。",
                        CanChangeInApplication: false);
                }

                _store.Delete(_valueName);
            }

            return await GetStateAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception exception) when (exception is UnauthorizedAccessException or IOException or SecurityException)
        {
            return FailedState(exception);
        }
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

    public string ExpectedCommandLine => $"\"{_executablePath}\" --startup";

    public static bool IsDevelopmentPath(string executablePath)
    {
        var normalized = Path.GetFullPath(executablePath)
            .Replace(Path.AltDirectorySeparatorChar, Path.DirectorySeparatorChar);
        var segments = normalized.Split(Path.DirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries);
        return segments.Any(segment => segment.Equals("bin", StringComparison.OrdinalIgnoreCase))
            || segments.Any(segment => segment.Equals("obj", StringComparison.OrdinalIgnoreCase))
            || normalized.StartsWith(Path.GetTempPath(), StringComparison.OrdinalIgnoreCase);
    }

    private static bool CommandLinesEqual(string left, string right) =>
        string.Equals(left.Trim(), right.Trim(), StringComparison.OrdinalIgnoreCase);

    private static LaunchAtLoginState DisabledState() => new(
        LaunchAtLoginStatus.Disabled,
        "已关闭；重新登录后不会自动启动。",
        CanChangeInApplication: true);

    private static LaunchAtLoginState EnabledState() => new(
        LaunchAtLoginStatus.Enabled,
        "已写入当前用户启动项，下次登录会自动启动。",
        CanChangeInApplication: true);

    private static LaunchAtLoginState NeedsStablePathState() => new(
        LaunchAtLoginStatus.NeedsStableApplicationPath,
        "开发或临时目录中的 Battuta 不会登记开机启动；请先使用正式 portable 或安装版。",
        CanChangeInApplication: false);

    private static LaunchAtLoginState FailedState(Exception exception) => new(
        LaunchAtLoginStatus.Failed,
        $"无法修改登录启动项：{exception.Message}",
        CanChangeInApplication: true);
}
