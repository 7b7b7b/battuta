using System.Diagnostics;

namespace Battuta.Windows.Updates;

public enum UpdateInstallerAvailability
{
    Ready,
    DevelopmentBuild,
    ManualDownloadOnly,
    NotConfigured,
}

public sealed record UpdateInstallResult(bool Started, string Message);

public interface IUpdateInstaller
{
    UpdateInstallerAvailability Availability { get; }

    Task<UpdateInstallResult> InstallAsync(
        GitHubReleaseSummary release,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Safe fallback for portable ZIP builds. It never attempts to overwrite the
/// running application directory.
/// </summary>
public sealed class ManualDownloadUpdateInstaller : IUpdateInstaller
{
    public UpdateInstallerAvailability Availability => UpdateInstallerAvailability.ManualDownloadOnly;

    public Task<UpdateInstallResult> InstallAsync(
        GitHubReleaseSummary release,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(release);
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            Process.Start(new ProcessStartInfo(release.ReleaseUri.AbsoluteUri)
            {
                UseShellExecute = true,
            });
            return Task.FromResult(new UpdateInstallResult(
                true,
                "已打开 GitHub Release，请下载并替换 portable 版本。"));
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            return Task.FromResult(new UpdateInstallResult(
                false,
                $"无法打开下载页面：{exception.Message}"));
        }
    }
}
