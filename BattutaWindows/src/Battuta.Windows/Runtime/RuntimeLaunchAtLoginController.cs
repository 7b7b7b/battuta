using Battuta.Windows.Startup;

namespace Battuta.Windows.Runtime;

/// <summary>Keeps the effective Windows startup state separate from the user's durable preference.</summary>
public sealed class RuntimeLaunchAtLoginController
{
    private readonly ILaunchAtLoginService? service;
    private LaunchAtLoginState? state;
    private long operationGeneration;

    public RuntimeLaunchAtLoginController(
        ILaunchAtLoginService? service,
        LaunchAtLoginState? initialState)
    {
        this.service = service;
        state = initialState;
    }

    public event EventHandler? StateChanged;

    public LaunchAtLoginState? State => Volatile.Read(ref state);

    public async Task<LaunchAtLoginState?> SetEnabledAsync(
        bool enabled,
        CancellationToken cancellationToken = default)
    {
        if (service is null)
        {
            return State;
        }

        var generation = Interlocked.Increment(ref operationGeneration);
        var next = await service.SetEnabledAsync(enabled, cancellationToken).ConfigureAwait(false);
        if (generation == Volatile.Read(ref operationGeneration))
        {
            Publish(next);
        }

        return next;
    }

    public async Task<LaunchAtLoginState?> RefreshAsync(
        CancellationToken cancellationToken = default)
    {
        if (service is null)
        {
            return State;
        }

        var generation = Interlocked.Increment(ref operationGeneration);
        var next = await service.GetStateAsync(cancellationToken).ConfigureAwait(false);
        if (generation == Volatile.Read(ref operationGeneration))
        {
            Publish(next);
        }

        return next;
    }

    public bool OpenSystemSettings()
    {
        if (service is null || State?.CanOpenSystemSettings == false)
        {
            return false;
        }

        return service.OpenSystemSettings();
    }

    private void Publish(LaunchAtLoginState next)
    {
        var previous = Interlocked.Exchange(ref state, next);
        if (!Equals(previous, next))
        {
            StateChanged?.Invoke(this, EventArgs.Empty);
        }
    }
}
