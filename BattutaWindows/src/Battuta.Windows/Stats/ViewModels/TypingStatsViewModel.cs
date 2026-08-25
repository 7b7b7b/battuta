using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Battuta.Windows.Stats.Models;
using Battuta.Windows.Stats.Services;

namespace Battuta.Windows.Stats.ViewModels;

public sealed class TypingStatsViewModel : ObservableObject, IDisposable
{
    private readonly TypingStatsRecorder _recorder;
    private readonly SemaphoreSlim _refreshGate = new(1, 1);
    private readonly SynchronizationContext? _synchronizationContext;
    private TypingStatsSnapshot? _snapshot;
    private TypingStatsSourceState _sourceState = TypingStatsSourceState.Checking;
    private string? _sourceErrorMessage;
    private bool _isRefreshing;
    private TypingTimelineRange _timelineRange = TypingTimelineRange.OneHour;
    private TypingRangeReportSnapshot? _reportSnapshot;
    private bool _isLoadingReport;
    private string? _reportErrorMessage;
    private int _reportRequestId;
    private bool _disposed;

    public TypingStatsViewModel(TypingStatsRecorder recorder)
    {
        _recorder = recorder ?? throw new ArgumentNullException(nameof(recorder));
        _synchronizationContext = SynchronizationContext.Current;
        _recorder.StateChanged += Recorder_StateChanged;
        RefreshCommand = new AsyncRelayCommand(RefreshAsync, () => !IsRefreshing);
        ClearAllCommand = new AsyncRelayCommand(ClearAllAsync, () => !IsClearing);
        RefreshReportCommand = new AsyncRelayCommand(RefreshCurrentReportAsync, () => !IsLoadingReport);
    }

    public IAsyncRelayCommand RefreshCommand { get; }

    public IAsyncRelayCommand ClearAllCommand { get; }

    public IAsyncRelayCommand RefreshReportCommand { get; }

    public TypingStatsSnapshot? Snapshot
    {
        get => _snapshot;
        private set
        {
            if (SetProperty(ref _snapshot, value))
            {
                OnPropertyChanged(nameof(StaleDataMessage));
            }
        }
    }

    public TypingStatsSourceState SourceState
    {
        get => _sourceState;
        private set
        {
            if (SetProperty(ref _sourceState, value))
            {
                OnPropertyChanged(nameof(StaleDataMessage));
            }
        }
    }

    public string? SourceErrorMessage
    {
        get => _sourceErrorMessage;
        private set
        {
            if (SetProperty(ref _sourceErrorMessage, value))
            {
                OnPropertyChanged(nameof(StaleDataMessage));
            }
        }
    }

    public bool IsRefreshing
    {
        get => _isRefreshing;
        private set
        {
            if (SetProperty(ref _isRefreshing, value))
            {
                RefreshCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public bool IsClearing => _recorder.IsClearing;

    public bool IsRecordingSuspended => _recorder.IsRecordingSuspended;

    public TypingTimelineRange TimelineRange
    {
        get => _timelineRange;
        private set => SetProperty(ref _timelineRange, value);
    }

    public TypingRangeReportSnapshot? ReportSnapshot
    {
        get => _reportSnapshot;
        private set => SetProperty(ref _reportSnapshot, value);
    }

    public bool IsLoadingReport
    {
        get => _isLoadingReport;
        private set
        {
            if (SetProperty(ref _isLoadingReport, value))
            {
                RefreshReportCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public string? ReportErrorMessage
    {
        get => _reportErrorMessage;
        private set => SetProperty(ref _reportErrorMessage, value);
    }

    public string? StaleDataMessage => Snapshot is null
        ? null
        : _recorder.LastWriteError ?? (SourceState == TypingStatsSourceState.Failed
            ? SourceErrorMessage
            : null);

    public async Task SelectTimelineRangeAsync(
        TypingTimelineRange range,
        CancellationToken cancellationToken = default)
    {
        if (TimelineRange == range)
        {
            return;
        }

        TimelineRange = range;
        await RefreshAsync(cancellationToken);
    }

    public async Task RefreshAsync(CancellationToken cancellationToken = default)
    {
        if (!await _refreshGate.WaitAsync(0, cancellationToken))
        {
            return;
        }

        IsRefreshing = true;
        try
        {
            var didFlush = await _recorder.FlushPendingAsync(cancellationToken);
            while (!cancellationToken.IsCancellationRequested)
            {
                var requestedRange = TimelineRange;
                try
                {
                    var loaded = await _recorder.Persistence.LoadSnapshotAsync(
                        requestedRange,
                        cancellationToken);
                    if (requestedRange != TimelineRange)
                    {
                        continue;
                    }

                    Snapshot = loaded;
                    if (didFlush)
                    {
                        SourceErrorMessage = null;
                        SourceState = TypingStatsSourceState.Available;
                    }
                    else
                    {
                        SourceErrorMessage = _recorder.LastWriteError;
                        SourceState = TypingStatsSourceState.Failed;
                    }

                    return;
                }
                catch (OperationCanceledException)
                {
                    return;
                }
                catch (Exception exception)
                {
                    if (requestedRange != TimelineRange)
                    {
                        continue;
                    }

                    SourceErrorMessage = exception.Message;
                    SourceState = TypingStatsSourceState.Failed;
                    return;
                }
            }
        }
        finally
        {
            IsRefreshing = false;
            _refreshGate.Release();
        }
    }

    public async Task LoadReportAsync(
        TypingDateRange range,
        TypingDateRange? comparisonRange,
        CancellationToken cancellationToken = default)
    {
        var requestId = Interlocked.Increment(ref _reportRequestId);
        IsLoadingReport = true;
        try
        {
            _ = await _recorder.FlushPendingAsync(cancellationToken);
            var report = await _recorder.Persistence.LoadReportAsync(
                range,
                comparisonRange,
                cancellationToken);
            if (requestId != Volatile.Read(ref _reportRequestId)
                || cancellationToken.IsCancellationRequested)
            {
                return;
            }

            ReportSnapshot = report;
            ReportErrorMessage = null;
        }
        catch (OperationCanceledException)
        {
            // A replacement request owns the visible state.
        }
        catch (Exception exception)
        {
            if (requestId == Volatile.Read(ref _reportRequestId))
            {
                ReportErrorMessage = exception.Message;
            }
        }
        finally
        {
            if (requestId == Volatile.Read(ref _reportRequestId))
            {
                IsLoadingReport = false;
            }
        }
    }

    public Task RefreshCurrentReportAsync(CancellationToken cancellationToken = default) =>
        ReportSnapshot is { } report
            ? LoadReportAsync(report.Range, report.ComparisonRange, cancellationToken)
            : Task.CompletedTask;

    public Task LoadAnnualReportAsync(
        DateOnly today,
        CancellationToken cancellationToken = default)
    {
        var ranges = TypingStatsReportRanges.Annual(today);
        return LoadReportAsync(ranges.Current, ranges.Comparison, cancellationToken);
    }

    public async Task ClearAllAsync(CancellationToken cancellationToken = default)
    {
        if (IsClearing)
        {
            return;
        }

        var previousReportRange = ReportSnapshot?.Range;
        var previousComparisonRange = ReportSnapshot?.ComparisonRange;
        try
        {
            await _recorder.ClearAllAsync(cancellationToken);
            Snapshot = await _recorder.Persistence.LoadSnapshotAsync(
                TimelineRange,
                cancellationToken);
            ReportSnapshot = previousReportRange is { } reportRange
                ? await _recorder.Persistence.LoadReportAsync(
                    reportRange,
                    previousComparisonRange,
                    cancellationToken)
                : null;
            ReportErrorMessage = null;
            SourceErrorMessage = null;
            SourceState = TypingStatsSourceState.Available;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception)
        {
            SourceErrorMessage = exception.Message;
            SourceState = TypingStatsSourceState.Failed;
        }
    }

    public async Task RunVisibleRefreshLoopAsync(CancellationToken cancellationToken)
    {
        await RefreshAsync(cancellationToken);
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimelineRange.GetDefinition().RefreshInterval, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }

            await RefreshAsync(cancellationToken);
        }
    }

    public async Task RunSummaryRefreshLoopAsync(CancellationToken cancellationToken)
    {
        await RefreshAsync(cancellationToken);
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(5));
        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            await RefreshAsync(cancellationToken);
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _recorder.StateChanged -= Recorder_StateChanged;
        _refreshGate.Dispose();
    }

    private void Recorder_StateChanged(object? sender, EventArgs e)
    {
        void Notify()
        {
            OnPropertyChanged(nameof(IsClearing));
            OnPropertyChanged(nameof(IsRecordingSuspended));
            OnPropertyChanged(nameof(StaleDataMessage));
            ClearAllCommand.NotifyCanExecuteChanged();
        }

        if (_synchronizationContext is not null
            && SynchronizationContext.Current != _synchronizationContext)
        {
            _synchronizationContext.Post(_ => Notify(), null);
        }
        else
        {
            Notify();
        }
    }
}

public sealed class TypingStatsSummaryViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly TypingStatsViewModel _model;

    public TypingStatsSummaryViewModel(TypingStatsViewModel model)
    {
        _model = model ?? throw new ArgumentNullException(nameof(model));
        _model.PropertyChanged += Model_PropertyChanged;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public long TodayCharacterCount => _model.Snapshot?.Today.CharacterCount ?? 0;

    public long TodayPeakCps => _model.Snapshot?.Today.PeakCps ?? 0;

    public string TopApplicationName => _model.Snapshot?.Today.TopAppName ?? "暂无";

    public bool HasSnapshot => _model.Snapshot is not null;

    public bool IsRecordingSuspended => _model.IsRecordingSuspended;

    public string? StaleDataMessage => _model.StaleDataMessage;

    public IAsyncRelayCommand RefreshCommand => _model.RefreshCommand;

    public void Dispose() => _model.PropertyChanged -= Model_PropertyChanged;

    private void Model_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(string.Empty));
    }
}
