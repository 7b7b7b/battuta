using System.Diagnostics;

namespace Battuta.Windows.Input;

public sealed record ForegroundApplicationSnapshot(
    int ProcessId,
    string ProcessKey,
    string DisplayName,
    string ProcessName)
{
    public static ForegroundApplicationSnapshot Unknown { get; } = new(
        0,
        "process:unknown",
        "未知应用",
        "unknown");
}

public interface IForegroundApplicationSnapshotProvider
{
    ForegroundApplicationSnapshot Current { get; }
}

/// <summary>
/// An atomic cache used by the input consumer. Publishing is generation-aware so a slow
/// process lookup from an older foreground notification cannot overwrite a newer result.
/// </summary>
public sealed class ForegroundApplicationCache : IForegroundApplicationSnapshotProvider
{
    private sealed record Entry(long Generation, ForegroundApplicationSnapshot Snapshot);

    private Entry _entry = new(0, ForegroundApplicationSnapshot.Unknown);

    public ForegroundApplicationSnapshot Current => Volatile.Read(ref _entry).Snapshot;

    public long Generation => Volatile.Read(ref _entry).Generation;

    public bool TryPublish(long generation, ForegroundApplicationSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);

        while (true)
        {
            var current = Volatile.Read(ref _entry);
            if (generation < current.Generation)
            {
                return false;
            }

            var replacement = new Entry(generation, snapshot);
            if (ReferenceEquals(
                Interlocked.CompareExchange(ref _entry, replacement, current),
                current))
            {
                return true;
            }
        }
    }
}

internal sealed class Win32ForegroundApplicationTracker
{
    private const uint EventSystemForeground = 0x0003;
    private const uint WineventOutOfContext = 0x0000;
    private const uint WineventSkipOwnProcess = 0x0002;

    private readonly ForegroundApplicationCache _cache;
    private readonly NativeMethods.WinEventDelegate _callback;
    private long _generation;
    private nint _hook;

    public Win32ForegroundApplicationTracker(ForegroundApplicationCache cache)
    {
        _cache = cache;
        _callback = OnForegroundChanged;
    }

    public bool StartOnCurrentMessageThread()
    {
        if (_hook != 0)
        {
            return true;
        }

        _hook = NativeMethods.SetWinEventHook(
            EventSystemForeground,
            EventSystemForeground,
            0,
            _callback,
            0,
            0,
            WineventOutOfContext | WineventSkipOwnProcess);

        var currentWindow = NativeMethods.GetForegroundWindow();
        if (currentWindow != 0)
        {
            QueueResolution(currentWindow);
        }

        return _hook != 0;
    }

    public void StopOnCurrentMessageThread()
    {
        if (_hook == 0)
        {
            return;
        }

        _ = NativeMethods.UnhookWinEvent(_hook);
        _hook = 0;
    }

    private void OnForegroundChanged(
        nint hook,
        uint eventType,
        nint window,
        int objectId,
        int childId,
        uint eventThread,
        uint eventTime)
    {
        if (window != 0)
        {
            QueueResolution(window);
        }
    }

    private void QueueResolution(nint window)
    {
        var generation = Interlocked.Increment(ref _generation);
        ThreadPool.UnsafeQueueUserWorkItem(
            static state => state.Tracker.ResolveAndPublish(state.Window, state.Generation),
            (Tracker: this, Window: window, Generation: generation),
            preferLocal: false);
    }

    private void ResolveAndPublish(nint window, long generation)
    {
        _ = NativeMethods.GetWindowThreadProcessId(window, out var processId);
        if (processId == 0)
        {
            _cache.TryPublish(generation, ForegroundApplicationSnapshot.Unknown);
            return;
        }

        try
        {
            using var process = Process.GetProcessById(checked((int)processId));
            var processName = process.ProcessName;
            if (string.IsNullOrWhiteSpace(processName))
            {
                processName = $"pid-{processId}";
            }

            _cache.TryPublish(generation, new ForegroundApplicationSnapshot(
                checked((int)processId),
                $"process:{processName.ToLowerInvariant()}",
                processName,
                processName));
        }
        catch (Exception exception) when (
            exception is ArgumentException
            or InvalidOperationException
            or System.ComponentModel.Win32Exception
            or NotSupportedException
            or UnauthorizedAccessException
            or OverflowException)
        {
            // Do not read a window title as a fallback. A PID-only identity is deliberately
            // avoided because it would fragment aggregate statistics on every launch.
            _cache.TryPublish(generation, ForegroundApplicationSnapshot.Unknown);
        }
    }
}
