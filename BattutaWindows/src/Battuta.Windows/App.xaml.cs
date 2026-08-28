using System.Windows;
using System.Windows.Threading;
using System.Windows.Interop;
using Battuta.Windows.Activation;
using Battuta.Windows.Bootstrap;
using Battuta.Windows.Audio;
using Battuta.Windows.Diy.ViewModels;
using Battuta.Windows.Runtime;
using Battuta.Windows.Tray;
using Battuta.Windows.Views.Diy;
using Battuta.Windows.Views.Stats;
using Battuta.Windows.Views.Tray;

namespace Battuta.Windows;

public partial class App : Application, IDisposable
{
    private BattutaRuntime? _runtime;
    private NativeTrayIconService? _trayIcon;
    private TrayFlyoutPlacementService? _trayPlacement;
    private TrayFlyoutWindow? _trayFlyout;
    private TypingStatsWindow? _statisticsWindow;
    private SoundPackEditorWindow? _diyWindow;
    private DiySoundPackEditorViewModel? _diyViewModel;
    private PixelPoint? _lastTrayAnchor;
    private readonly SemaphoreSlim _diyOpenGate = new(1, 1);
    private int _shutdownStarted;

    public App()
    {
        DispatcherUnhandledException += OnDispatcherUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += OnDomainUnhandledException;
        TaskScheduler.UnobservedTaskException += OnUnobservedTaskException;
    }

    public BattutaRuntime Runtime => _runtime
        ?? throw new InvalidOperationException("Battuta has not completed startup.");

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        try
        {
            var platform = await PlatformBootstrapper.StartAsync(
                e.Args,
                SynchronizationContext.Current);
            if (!platform.IsPrimary)
            {
                await platform.DisposeAsync();
                Shutdown(platform.ActivationDelivered ? 0 : 2);
                return;
            }

            _runtime = new BattutaRuntime(platform);
            await _runtime.StartAsync();

            var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "Battuta.ico");
            var iconHandle = NativeTrayIconService.LoadIconFromFile(iconPath, 32);
            _trayIcon = new NativeTrayIconService(
                iconHandle,
                $"Battuta - {_runtime.StatusText}",
                ownsIconHandle: true,
                useGuidIdentifier: false);
            _trayPlacement = new TrayFlyoutPlacementService(_trayIcon);
            _trayIcon.Invoked += TrayIconInvoked;
            await _trayIcon.ShowAsync();

            if (platform.SingleInstance is not null)
            {
                platform.SingleInstance.ActivationReceived += ActivationReceived;
            }

            HandleActivation(platform.Activation);
        }
        catch (Exception exception)
        {
            LogUnhandled(exception);
            MessageBox.Show(
                $"Battuta 启动失败：{exception.Message}",
                "Battuta",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            await DisposeRuntimeAsync();
            Shutdown(1);
        }
    }

    public void ShowStatisticsWindow()
    {
        if (_runtime is null)
        {
            return;
        }

        if (_statisticsWindow is null)
        {
            _statisticsWindow = new TypingStatsWindow
            {
                DataContext = _runtime.StatisticsViewModel,
            };
            _statisticsWindow.Closed += (_, _) => _statisticsWindow = null;
        }

        ShowAndActivate(_statisticsWindow);
        _ = _runtime.StatisticsViewModel.RefreshAsync();
    }

    public void ShowDiyWindow() => _ = ShowDiyWindowAsync(soundPackPath: null);

    private async Task ShowDiyWindowAsync(string? soundPackPath)
    {
        if (_runtime is null)
        {
            return;
        }

        await _diyOpenGate.WaitAsync();
        try
        {
            if (_diyWindow is null)
            {
                var resources = new BuiltInAudioResourceCatalog();
                _diyViewModel = new DiySoundPackEditorViewModel(
                    _runtime.SoundPackLibrary,
                    _runtime.Settings.SelectedProfileId,
                    previewService: new DiyAudioPreviewService(
                        _runtime.AudioEngine,
                        volumeProvider: () => _runtime.Settings.Volume),
                    builtInAudioLocator: new DiyBuiltInAudioLocator(resources),
                    temporaryCacheParent: _runtime.Paths.TemporaryDirectory,
                    onLibraryChanged: OnDiyLibraryChangedAsync);
                _diyWindow = new SoundPackEditorWindow
                {
                    DataContext = _diyViewModel,
                };
                _diyWindow.Closed += DiyWindowClosed;
                ShowAndActivate(_diyWindow);
                await _diyViewModel.LoadInitialStateAsync();
            }

            if (_diyWindow is not null)
            {
                ShowAndActivate(_diyWindow);
                if (!string.IsNullOrWhiteSpace(soundPackPath))
                {
                    _ = await _diyWindow.RequestImportPackAsync(soundPackPath);
                }
            }
        }
        catch (Exception exception)
        {
            LogUnhandled(exception);
            MessageBox.Show(
                $"无法打开 DIY 音色编辑器：{exception.Message}",
                "Battuta",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        finally
        {
            _diyOpenGate.Release();
        }
    }

    public async Task RequestShutdownAsync()
    {
        if (Interlocked.Exchange(ref _shutdownStarted, 1) != 0)
        {
            return;
        }

        try
        {
            if (_diyWindow is not null
                && !await _diyWindow.PrepareForApplicationExitAsync())
            {
                Volatile.Write(ref _shutdownStarted, 0);
                return;
            }

            _trayFlyout?.DismissFromTray();
            await DisposeRuntimeAsync();
            _trayIcon?.Hide();
            _trayIcon?.Dispose();
            _trayIcon = null;
            Shutdown();
        }
        catch
        {
            if (_trayIcon is { IsVisible: false })
            {
                await _trayIcon.ShowAsync();
            }

            Volatile.Write(ref _shutdownStarted, 0);
            throw;
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        try
        {
            Dispose();
        }
        catch (Exception exception)
        {
            LogUnhandled(exception);
        }
        base.OnExit(e);
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _shutdownStarted, 1) == 0)
        {
            DisposeRuntimeAsync().GetAwaiter().GetResult();
        }

        _trayIcon?.Dispose();
        _trayIcon = null;
        GC.SuppressFinalize(this);
    }

    private void ActivationReceived(object? sender, ActivationRequest activation) =>
        HandleActivation(activation);

    private void HandleActivation(ActivationRequest activation)
    {
        switch (activation.Kind)
        {
            case ActivationKind.Startup:
                break;
            case ActivationKind.ShowStatistics:
                ShowStatisticsWindow();
                break;
            case ActivationKind.ShowDiyEditor:
                ShowDiyWindow();
                break;
            case ActivationKind.OpenSoundPack:
                _ = ShowDiyWindowAsync(activation.FilePath);
                break;
            default:
                ShowTrayFlyout(toggle: false);
                break;
        }
    }

    private void TrayIconInvoked(object? sender, TrayIconInvokedEventArgs e)
    {
        _lastTrayAnchor = e.ScreenPoint ?? _lastTrayAnchor;
        if (e.Invocation == TrayIconInvocation.ContextMenu)
        {
            ShowTrayContextMenu(e.ScreenPoint);
            return;
        }

        ShowTrayFlyout(toggle: true, e.ScreenPoint);
    }

    private void ShowTrayFlyout(bool toggle, PixelPoint? anchor = null)
    {
        if (_runtime is null || _trayPlacement is null)
        {
            return;
        }

        _trayFlyout ??= CreateTrayFlyout(_runtime);
        if (toggle && _trayFlyout.IsVisible)
        {
            _trayFlyout.DismissFromTray();
            return;
        }

        _trayFlyout.ShowFromTray(_trayPlacement, anchor ?? _lastTrayAnchor);
        _trayIcon?.SetTooltip($"Battuta - {_runtime.StatusText}");
        _ = _runtime.StatisticsViewModel.RefreshAsync();
    }

    private TrayFlyoutWindow CreateTrayFlyout(BattutaRuntime runtime)
    {
        var window = new TrayFlyoutWindow();
        window.AttachRuntime(runtime);
        window.ConfigureActions(
            ShowStatisticsWindow,
            ShowDiyWindow,
            RequestShutdownAsync);
        window.ActionFailed += (_, exception) => ReportUiActionFailure(exception);
        return window;
    }

    private void ShowTrayContextMenu(PixelPoint? anchor)
    {
        _trayFlyout?.DismissForContextMenu();
        if (_trayIcon is null)
        {
            return;
        }

        TrayContextMenuCommand command;
        try
        {
            command = TrayContextMenuFactory.Show(
                _trayIcon.OwnerWindowHandle,
                anchor ?? _lastTrayAnchor);
        }
        catch (Exception exception)
        {
            ReportUiActionFailure(exception);
            return;
        }

        if (command == TrayContextMenuCommand.None)
        {
            return;
        }

        _ = Dispatcher.BeginInvoke(
            DispatcherPriority.ContextIdle,
            async () => await ExecuteTrayContextMenuCommandAsync(command, anchor));
    }

    private async Task ExecuteTrayContextMenuCommandAsync(
        TrayContextMenuCommand command,
        PixelPoint? anchor)
    {
        try
        {
            switch (command)
            {
                case TrayContextMenuCommand.OpenPanel:
                    ShowTrayFlyout(toggle: false, anchor);
                    break;
                case TrayContextMenuCommand.OpenStatistics:
                    ShowStatisticsWindow();
                    break;
                case TrayContextMenuCommand.OpenDiyEditor:
                    ShowDiyWindow();
                    break;
                case TrayContextMenuCommand.ExitApplication:
                    await RequestShutdownAsync();
                    break;
            }
        }
        catch (Exception exception)
        {
            ReportUiActionFailure(exception);
        }
    }

    private static void ReportUiActionFailure(Exception exception)
    {
        LogUnhandled(exception);
        MessageBox.Show(
            $"无法完成操作：{exception.Message}",
            "Battuta",
            MessageBoxButton.OK,
            MessageBoxImage.Error);
    }

    private static void ShowAndActivate(Window window)
    {
        if (!window.IsVisible)
        {
            window.Show();
        }

        if (window.WindowState == WindowState.Minimized)
        {
            window.WindowState = WindowState.Normal;
        }

        var handle = new WindowInteropHelper(window).EnsureHandle();
        _ = ShowWindow(handle, 9); // SW_RESTORE
        _ = SetForegroundWindow(handle);
        _ = window.Activate();
        _ = window.Dispatcher.BeginInvoke(
            DispatcherPriority.Input,
            () =>
            {
                if (!window.IsVisible)
                {
                    return;
                }

                _ = SetForegroundWindow(handle);
                _ = window.Activate();
                _ = window.Focus();
            });
    }

    private async Task DisposeRuntimeAsync()
    {
        if (_diyViewModel is not null)
        {
            await _diyViewModel.DisposeAsync();
            _diyViewModel = null;
        }

        var runtime = Interlocked.Exchange(ref _runtime, null);
        if (runtime is not null)
        {
            await runtime.DisposeAsync();
        }
    }

    private async Task OnDiyLibraryChangedAsync(string? selectionId)
    {
        if (_runtime is null || string.IsNullOrWhiteSpace(selectionId))
        {
            return;
        }

        _ = await _runtime.ActivateSoundPackAsync(selectionId);
    }

    private async void DiyWindowClosed(object? sender, EventArgs e)
    {
        _diyWindow = null;
        if (_diyViewModel is not null)
        {
            await _diyViewModel.DisposeAsync();
            _diyViewModel = null;
        }
    }

    private void OnDispatcherUnhandledException(
        object sender,
        DispatcherUnhandledExceptionEventArgs e)
    {
        LogUnhandled(e.Exception);
        e.Handled = true;
        MessageBox.Show(
            $"Battuta 遇到错误，但已阻止系统崩溃弹窗：{e.Exception.Message}",
            "Battuta",
            MessageBoxButton.OK,
            MessageBoxImage.Error);
    }

    private static void OnDomainUnhandledException(object sender, UnhandledExceptionEventArgs e)
    {
        if (e.ExceptionObject is Exception exception)
        {
            LogUnhandled(exception);
        }
    }

    private static void OnUnobservedTaskException(object? sender, UnobservedTaskExceptionEventArgs e)
    {
        LogUnhandled(e.Exception);
        e.SetObserved();
    }

    private static void LogUnhandled(Exception exception)
    {
        try
        {
            var directory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Battuta",
                "Logs");
            Directory.CreateDirectory(directory);
            File.AppendAllText(
                Path.Combine(directory, "unhandled.log"),
                $"[{DateTimeOffset.Now:O}] {exception}\n\n",
                Encoding.UTF8);
        }
        catch
        {
            // Logging must never replace the original failure.
        }
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindow(IntPtr window, int command);
}
