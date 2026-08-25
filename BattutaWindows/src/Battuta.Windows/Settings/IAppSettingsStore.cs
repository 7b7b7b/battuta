namespace Battuta.Windows.Settings;

public interface IAppSettingsStore
{
    Task<AppSettingsSnapshot> LoadAsync(CancellationToken cancellationToken = default);

    Task SaveAsync(AppSettingsSnapshot settings, CancellationToken cancellationToken = default);
}
