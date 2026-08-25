using System.Windows;

namespace Battuta.Windows.Lifecycle;

/// <summary>
/// Thin WPF adapter around ExitCoordinator. App.xaml.cs remains responsible for
/// deciding when to attach it and for registering concrete exit participants.
/// </summary>
public sealed class ApplicationLifecycleService : IDisposable
{
    private readonly Application _application;
    private readonly ExitCoordinator _exitCoordinator;
    private bool _attached;
    private bool _disposed;

    public ApplicationLifecycleService(Application application, ExitCoordinator exitCoordinator)
    {
        _application = application ?? throw new ArgumentNullException(nameof(application));
        _exitCoordinator = exitCoordinator ?? throw new ArgumentNullException(nameof(exitCoordinator));
    }

    public void Attach()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_attached)
        {
            return;
        }

        _application.SessionEnding += OnSessionEnding;
        _attached = true;
    }

    public async Task<ExitOutcome> RequestExitAsync(
        ExitReason reason = ExitReason.UserRequested,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var outcome = await _exitCoordinator.RequestExitAsync(reason, cancellationToken);
        if (outcome == ExitOutcome.Completed)
        {
            _application.Dispatcher.Invoke(() => _application.Shutdown());
        }

        return outcome;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        if (_attached)
        {
            _application.SessionEnding -= OnSessionEnding;
            _attached = false;
        }
    }

    private void OnSessionEnding(object sender, SessionEndingCancelEventArgs e)
    {
        // Windows can terminate the process shortly after this notification.
        // Use a short synchronous budget and never block sign-out indefinitely.
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        try
        {
            _exitCoordinator.RequestExitAsync(ExitReason.SystemSessionEnding, cancellation.Token)
                .GetAwaiter()
                .GetResult();
        }
        catch (OperationCanceledException)
        {
        }
    }
}
