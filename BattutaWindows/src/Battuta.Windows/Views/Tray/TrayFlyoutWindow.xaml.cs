using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Battuta.Windows.Tray;
using Battuta.Windows.Views.Diy;
using Battuta.Windows.Views.Stats;

namespace Battuta.Windows.Views.Tray;

public partial class TrayFlyoutWindow : Window, IDisposable
{
    private const int SwRestore = 9;
    private Action? _showStatistics;
    private Action? _showDiyEditor;
    private Func<Task>? _requestExit;
    private DateTime _ignoreDeactivationUntilUtc;
    private int _deactivationGeneration;
    private int _interactivePopupDepth;
    private readonly HashSet<Popup> _openInteractivePopups = [];
    private readonly Dictionary<Popup, ComboBox> _interactivePopupOwners = [];
    private readonly Dictionary<UIElement, ComboBox> _interactivePopupContentOwners = [];
    private Popup? _keyboardProfilePopup;
    private Popup? _pointerProfilePopup;
    private bool _actionInProgress;

    public TrayFlyoutWindow()
    {
        InitializeComponent();
        Deactivated += WindowDeactivated;
        Activated += WindowActivated;
        Loaded += WindowLoaded;
        Closed += WindowClosed;
        PreviewMouseDown += WindowPreviewMouseDown;
    }

    public event EventHandler<Exception>? ActionFailed;

    public void ConfigureActions(
        Action showStatistics,
        Action showDiyEditor,
        Func<Task> requestExit)
    {
        _showStatistics = showStatistics ?? throw new ArgumentNullException(nameof(showStatistics));
        _showDiyEditor = showDiyEditor ?? throw new ArgumentNullException(nameof(showDiyEditor));
        _requestExit = requestExit ?? throw new ArgumentNullException(nameof(requestExit));
    }

    public void ShowFromTray(
        TrayFlyoutPlacementService placementService,
        PixelPoint? fallbackAnchor = null)
    {
        ArgumentNullException.ThrowIfNull(placementService);
        Dispatcher.VerifyAccess();
        SuppressAutoDismiss(TimeSpan.FromMilliseconds(400));
        if (!IsVisible)
        {
            Show();
        }

        UpdateLayout();
        _ = placementService.TryPlace(this, fallbackAnchor);
        ActivateFromTray();
    }

    public void ActivateFromTray()
    {
        Dispatcher.VerifyAccess();
        SuppressAutoDismiss(TimeSpan.FromMilliseconds(400));
        var handle = new WindowInteropHelper(this).EnsureHandle();
        _ = ShowWindow(handle, SwRestore);
        _ = SetForegroundWindow(handle);
        _ = Activate();
        _ = Dispatcher.BeginInvoke(
            DispatcherPriority.Input,
            () =>
            {
                if (!IsVisible)
                {
                    return;
                }

                _ = SetForegroundWindow(handle);
                _ = Activate();
                _ = Focus();
            });
    }

    public void DismissForContextMenu()
    {
        Dispatcher.VerifyAccess();
        SuppressAutoDismiss(TimeSpan.FromMilliseconds(250));
        Dismiss();
    }

    public void DismissFromTray()
    {
        Dispatcher.VerifyAccess();
        Dismiss();
    }

    private void DismissClick(object sender, RoutedEventArgs e) => Dismiss();

    private async void ExitClick(object sender, RoutedEventArgs e)
    {
        if (_actionInProgress)
        {
            return;
        }

        _actionInProgress = true;
        ExitButton.IsEnabled = false;
        DismissButton.IsEnabled = false;
        SuppressAutoDismiss(TimeSpan.FromSeconds(5));
        try
        {
            if (_requestExit is not null)
            {
                await _requestExit();
            }
            else if (Application.Current is App app)
            {
                await app.RequestShutdownAsync();
            }
            else
            {
                Application.Current.Shutdown();
            }
        }
        catch (Exception exception)
        {
            ReportActionFailure(exception);
        }
        finally
        {
            if (Application.Current?.Dispatcher.HasShutdownStarted != true)
            {
                _actionInProgress = false;
                ExitButton.IsEnabled = true;
                DismissButton.IsEnabled = true;
            }
        }
    }

    private void OpenStatsClick(object sender, RoutedEventArgs e)
    {
        var action = _showStatistics;
        if (action is null && Application.Current is App app)
        {
            action = app.ShowStatisticsWindow;
        }

        Dismiss();
        if (action is not null)
        {
            ScheduleAction(action);
            return;
        }

        ScheduleAction(() => new TypingStatsWindow().Show());
    }

    private void OpenDiyClick(object sender, RoutedEventArgs e)
    {
        var action = _showDiyEditor;
        if (action is null && Application.Current is App app)
        {
            action = app.ShowDiyWindow;
        }

        Dismiss();
        if (action is not null)
        {
            ScheduleAction(action);
            return;
        }

        ScheduleAction(() => new SoundPackEditorWindow().Show());
    }

    private void WindowKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape)
        {
            return;
        }

        e.Handled = true;
        Dismiss();
    }

    private void WindowActivated(object? sender, EventArgs e) =>
        Interlocked.Increment(ref _deactivationGeneration);

    private void WindowDeactivated(object? sender, EventArgs e)
    {
        var generation = Interlocked.Increment(ref _deactivationGeneration);
        _ = Dispatcher.BeginInvoke(
            DispatcherPriority.ContextIdle,
            () => EvaluateAutoDismiss(generation));
    }

    private void WindowPreviewMouseDown(object sender, MouseButtonEventArgs e)
    {
        SuppressAutoDismiss(
            KeyboardProfileCombo.IsMouseOver || PointerProfileCombo.IsMouseOver
                ? TimeSpan.FromSeconds(1)
                : TimeSpan.FromMilliseconds(350));
    }

    private void WindowLoaded(object sender, RoutedEventArgs e)
    {
        _keyboardProfilePopup = AttachInteractivePopupLifecycle(KeyboardProfileCombo);
        _pointerProfilePopup = AttachInteractivePopupLifecycle(PointerProfileCombo);
    }

    private void WindowClosed(object? sender, EventArgs e)
    {
        DetachInteractivePopupLifecycle(_keyboardProfilePopup);
        DetachInteractivePopupLifecycle(_pointerProfilePopup);
        _keyboardProfilePopup = null;
        _pointerProfilePopup = null;
        _openInteractivePopups.Clear();
        _interactivePopupOwners.Clear();
        _interactivePopupContentOwners.Clear();
        _interactivePopupDepth = 0;
    }

    private Popup? AttachInteractivePopupLifecycle(ComboBox comboBox)
    {
        _ = comboBox.ApplyTemplate();
        if (comboBox.Template.FindName("PART_Popup", comboBox) is not Popup popup)
        {
            return null;
        }

        popup.Opened -= InteractivePopupOpened;
        popup.Closed -= InteractivePopupClosed;
        popup.Opened += InteractivePopupOpened;
        popup.Closed += InteractivePopupClosed;
        _interactivePopupOwners[popup] = comboBox;
        if (popup.Child is UIElement popupContent)
        {
            popupContent.RemoveHandler(
                UIElement.PreviewMouseLeftButtonUpEvent,
                new MouseButtonEventHandler(InteractivePopupPreviewMouseLeftButtonUp));
            popupContent.AddHandler(
                UIElement.PreviewMouseLeftButtonUpEvent,
                new MouseButtonEventHandler(InteractivePopupPreviewMouseLeftButtonUp),
                handledEventsToo: true);
            _interactivePopupContentOwners[popupContent] = comboBox;
        }

        return popup;
    }

    private void DetachInteractivePopupLifecycle(Popup? popup)
    {
        if (popup is null)
        {
            return;
        }

        popup.Opened -= InteractivePopupOpened;
        popup.Closed -= InteractivePopupClosed;
        _ = _interactivePopupOwners.Remove(popup);
        if (popup.Child is UIElement popupContent)
        {
            popupContent.RemoveHandler(
                UIElement.PreviewMouseLeftButtonUpEvent,
                new MouseButtonEventHandler(InteractivePopupPreviewMouseLeftButtonUp));
            _ = _interactivePopupContentOwners.Remove(popupContent);
        }
    }

    private void InteractivePopupPreviewMouseLeftButtonUp(
        object sender,
        MouseButtonEventArgs e)
    {
        if (sender is not UIElement popupContent
            || !_interactivePopupContentOwners.TryGetValue(popupContent, out var comboBox)
            || comboBox.IsEnabled != true)
        {
            return;
        }

        var container = FindComboBoxItem(e.OriginalSource as DependencyObject);
        if (container is null
            || !ReferenceEquals(ItemsControl.ItemsControlFromItemContainer(container), comboBox))
        {
            return;
        }

        var item = comboBox.ItemContainerGenerator.ItemFromContainer(container);
        if (ReferenceEquals(item, DependencyProperty.UnsetValue))
        {
            return;
        }

        comboBox.SelectedItem = item;
        comboBox.IsDropDownOpen = false;
        e.Handled = true;
    }

    private static ComboBoxItem? FindComboBoxItem(DependencyObject? source)
    {
        for (var current = source; current is not null;)
        {
            if (current is ComboBoxItem item)
            {
                return item;
            }

            current = current is Visual
                ? VisualTreeHelper.GetParent(current)
                : LogicalTreeHelper.GetParent(current);
        }

        return null;
    }

    private void InteractivePopupOpened(object? sender, EventArgs e)
    {
        if (sender is Popup popup)
        {
            _ = _openInteractivePopups.Add(popup);
            _interactivePopupDepth = _openInteractivePopups.Count;
        }

        SuppressAutoDismiss(TimeSpan.FromSeconds(1));
        Interlocked.Increment(ref _deactivationGeneration);
    }

    private void InteractivePopupClosed(object? sender, EventArgs e)
    {
        if (sender is Popup popup)
        {
            _ = _openInteractivePopups.Remove(popup);
            _interactivePopupDepth = _openInteractivePopups.Count;
        }
        else
        {
            _interactivePopupDepth = Math.Max(0, _interactivePopupDepth - 1);
        }

        ApplyDeferredSoundPackChoicesAfterPopupClosed();
        SuppressAutoDismiss(TimeSpan.FromMilliseconds(200));
        var generation = Interlocked.Increment(ref _deactivationGeneration);
        _ = Dispatcher.BeginInvoke(
            DispatcherPriority.ContextIdle,
            () => EvaluateAutoDismiss(generation));
    }

    private void EvaluateAutoDismiss(int generation)
    {
        if (!IsVisible
            || generation != _deactivationGeneration
            || IsInteractivePopupOpen())
        {
            return;
        }

        var remainingSuppression = _ignoreDeactivationUntilUtc - DateTime.UtcNow;
        if (remainingSuppression > TimeSpan.Zero)
        {
            _ = EvaluateAfterSuppressionAsync(generation, remainingSuppression);
            return;
        }

        var foreground = GetForegroundWindow();
        if (foreground != IntPtr.Zero
            && foreground == new WindowInteropHelper(this).Handle)
        {
            return;
        }

        Dismiss();
    }

    private bool IsInteractivePopupOpen() =>
        _interactivePopupDepth > 0
        || KeyboardProfileCombo.IsDropDownOpen
        || PointerProfileCombo.IsDropDownOpen
        || _keyboardProfilePopup?.IsOpen == true
        || _pointerProfilePopup?.IsOpen == true;

    private async Task EvaluateAfterSuppressionAsync(int generation, TimeSpan delay)
    {
        try
        {
            await Task.Delay(delay);
        }
        catch (ArgumentOutOfRangeException)
        {
            return;
        }

        if (!Dispatcher.HasShutdownStarted)
        {
            EvaluateAutoDismiss(generation);
        }
    }

    private void SuppressAutoDismiss(TimeSpan duration)
    {
        var until = DateTime.UtcNow.Add(duration);
        if (until > _ignoreDeactivationUntilUtc)
        {
            _ignoreDeactivationUntilUtc = until;
        }
    }

    private void Dismiss()
    {
        KeyboardProfileCombo.IsDropDownOpen = false;
        PointerProfileCombo.IsDropDownOpen = false;
        Interlocked.Increment(ref _deactivationGeneration);
        if (IsVisible)
        {
            Hide();
        }
    }

    private void ScheduleAction(Action action)
    {
        _ = Dispatcher.BeginInvoke(
            DispatcherPriority.Background,
            () =>
            {
                try
                {
                    action();
                }
                catch (Exception exception)
                {
                    ReportActionFailure(exception);
                }
            });
    }

    private void ReportActionFailure(Exception exception)
    {
        var handler = ActionFailed;
        handler?.Invoke(this, exception);
        if (handler is null)
        {
            MessageBox.Show(
                $"无法完成操作：{exception.Message}",
                "Battuta",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindow(IntPtr window, int command);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

}
