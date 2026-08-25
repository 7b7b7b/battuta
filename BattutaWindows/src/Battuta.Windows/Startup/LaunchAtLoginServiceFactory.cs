using Battuta.Windows.Platform;

namespace Battuta.Windows.Startup;

public static class LaunchAtLoginServiceFactory
{
    public static ILaunchAtLoginService Create(
        string executablePath,
        PackageIdentityInfo? identity = null,
        IStartupEntryStore? registryStore = null)
    {
        identity ??= PackageIdentityDetector.GetCurrent();
        return identity.IsPackaged
            ? new PackagedLaunchAtLoginService()
            : new RegistryLaunchAtLoginService(executablePath, registryStore);
    }
}
