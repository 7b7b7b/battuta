using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using Battuta.Core.Input;

namespace Battuta.Windows.Input;

public readonly record struct WindowsHookStartResult(
    bool KeyboardHookStarted,
    bool PointerHookStarted,
    int ErrorCode)
{
    public bool Started => KeyboardHookStarted;
}

/// <summary>
/// Owns the low-level Windows hooks and their dedicated Win32 message thread.
/// Hook callbacks never await or invoke consumers directly.
/// </summary>
public sealed class Win32InputHookService : IAsyncDisposable
{
    private const uint ReinstallHooksMessage = NativeMethods.WmApp + 0x41;
    private const int DefaultQueueCapacity = 1024;

    public static readonly nuint SyntheticInputSentinel = 0x42545441u; // "BTTA"

    private readonly IWindowsInputEventSink _sink;
    private readonly IForegroundApplicationSnapshotProvider _foregroundApplications;
    private readonly ForegroundApplicationCache? _ownedForegroundCache;
    private readonly TimeProvider _timeProvider;
    private readonly BoundedWindowsInputEventBuffer _queue;
    private readonly WindowsKeyboardRepeatTracker _repeatTracker = new();
    private readonly WindowsKeyboardEventNormalizer _normalizer = new();
    private readonly NativeMethods.HookProcedure _keyboardCallback;
    private readonly NativeMethods.HookProcedure _mouseCallback;
    private readonly TaskCompletionSource<WindowsHookStartResult> _startCompletion =
        new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly TaskCompletionSource _threadExitCompletion =
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    private Task? _consumerTask;
    private Thread? _hookThread;
    private Win32ForegroundApplicationTracker? _foregroundTracker;
    private nint _keyboardHook;
    private nint _mouseHook;
    private uint _hookThreadId;
    private ulong _nextSequence;
    private long _lastHookCallbackTimestamp;
    private int _acceptingEvents;
    private int _lifecycle;
    private Exception? _lastCallbackError;
    private Exception? _lastConsumerError;

    public Win32InputHookService(
        IWindowsInputEventSink sink,
        IForegroundApplicationSnapshotProvider? foregroundApplications = null,
        TimeProvider? timeProvider = null,
        int queueCapacity = DefaultQueueCapacity)
    {
        ArgumentNullException.ThrowIfNull(sink);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(queueCapacity);

        _sink = sink;
        _timeProvider = timeProvider ?? TimeProvider.System;
        if (foregroundApplications is null)
        {
            _ownedForegroundCache = new ForegroundApplicationCache();
            _foregroundApplications = _ownedForegroundCache;
        }
        else
        {
            _foregroundApplications = foregroundApplications;
        }

        _queue = new BoundedWindowsInputEventBuffer(queueCapacity);

        _keyboardCallback = KeyboardHookCallback;
        _mouseCallback = MouseHookCallback;
    }

    public bool IsRunning => Volatile.Read(ref _acceptingEvents) != 0;

    public long DroppedEventCount => _queue.DroppedCount;

    public long LastHookCallbackTimestamp => Interlocked.Read(ref _lastHookCallbackTimestamp);

    public Exception? LastCallbackError => Volatile.Read(ref _lastCallbackError);

    public Exception? LastConsumerError => Volatile.Read(ref _lastConsumerError);

    public IForegroundApplicationSnapshotProvider ForegroundApplications =>
        _foregroundApplications;

    public async Task<WindowsHookStartResult> StartAsync(
        CancellationToken cancellationToken = default)
    {
        if (Interlocked.CompareExchange(ref _lifecycle, 1, 0) != 0)
        {
            throw new InvalidOperationException("The input hook service can only be started once.");
        }

        _consumerTask = ConsumeQueueAsync();
        _hookThread = new Thread(HookThreadMain)
        {
            IsBackground = true,
            Name = "Battuta Win32 input hooks",
        };
        _hookThread.SetApartmentState(ApartmentState.MTA);
        _hookThread.Start();

        return await _startCompletion.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
    }

    public bool RequestReinstall()
    {
        var threadId = Volatile.Read(ref _hookThreadId);
        return threadId != 0
            && NativeMethods.PostThreadMessageW(threadId, ReinstallHooksMessage, 0, 0);
    }

    public async Task StopAsync(CancellationToken cancellationToken = default)
    {
        var previous = Interlocked.Exchange(ref _lifecycle, 2);
        if (previous is 2 or 3)
        {
            await _threadExitCompletion.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
            return;
        }

        Volatile.Write(ref _acceptingEvents, 0);
        var threadId = Volatile.Read(ref _hookThreadId);
        if (threadId != 0)
        {
            _ = NativeMethods.PostThreadMessageW(threadId, NativeMethods.WmQuit, 0, 0);
        }
        else if (previous == 1)
        {
            _ = await _startCompletion.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
            threadId = Volatile.Read(ref _hookThreadId);
            if (threadId != 0)
            {
                _ = NativeMethods.PostThreadMessageW(threadId, NativeMethods.WmQuit, 0, 0);
            }
        }
        else
        {
            _queue.TryComplete();
            _threadExitCompletion.TrySetResult();
        }

        await _threadExitCompletion.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
        if (_consumerTask is not null)
        {
            await _consumerTask.WaitAsync(cancellationToken).ConfigureAwait(false);
        }

        Volatile.Write(ref _lifecycle, 3);
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync().ConfigureAwait(false);
        GC.SuppressFinalize(this);
    }

    private void HookThreadMain()
    {
        var startReported = false;
        try
        {
            _hookThreadId = NativeMethods.GetCurrentThreadId();
            _ = NativeMethods.PeekMessageW(out _, 0, 0, 0, 0);
            PrepareHotPath();

            if (_ownedForegroundCache is not null)
            {
                _foregroundTracker = new Win32ForegroundApplicationTracker(_ownedForegroundCache);
                _ = _foregroundTracker.StartOnCurrentMessageThread();
            }

            var result = InstallHooks();
            startReported = true;
            _startCompletion.TrySetResult(result);
            if (!result.KeyboardHookStarted)
            {
                return;
            }

            Volatile.Write(ref _acceptingEvents, 1);
            while (true)
            {
                var getMessageResult = NativeMethods.GetMessageW(out var message, 0, 0, 0);
                if (getMessageResult == 0)
                {
                    break;
                }

                if (getMessageResult < 0)
                {
                    Volatile.Write(
                        ref _lastCallbackError,
                        new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()));
                    break;
                }

                if (message.Id == ReinstallHooksMessage)
                {
                    ReinstallHooksOnCurrentThread();
                    continue;
                }

                _ = NativeMethods.TranslateMessage(in message);
                _ = NativeMethods.DispatchMessageW(in message);
            }
        }
        catch (Exception exception)
        {
            Volatile.Write(ref _lastCallbackError, exception);
            if (!startReported)
            {
                _startCompletion.TrySetResult(new WindowsHookStartResult(
                    false,
                    false,
                    Marshal.GetLastWin32Error()));
            }
        }
        finally
        {
            Volatile.Write(ref _acceptingEvents, 0);
            UninstallHooks();
            _foregroundTracker?.StopOnCurrentMessageThread();
            _queue.TryComplete();
            _hookThreadId = 0;
            _threadExitCompletion.TrySetResult();
        }
    }

    private WindowsHookStartResult InstallHooks()
    {
        var module = NativeMethods.GetModuleHandleW(null);
        _keyboardHook = NativeMethods.SetWindowsHookExW(
            NativeMethods.WhKeyboardLl,
            _keyboardCallback,
            module,
            0);
        if (_keyboardHook == 0)
        {
            return new WindowsHookStartResult(false, false, Marshal.GetLastWin32Error());
        }

        _mouseHook = NativeMethods.SetWindowsHookExW(
            NativeMethods.WhMouseLl,
            _mouseCallback,
            module,
            0);
        var mouseError = _mouseHook == 0 ? Marshal.GetLastWin32Error() : 0;
        return new WindowsHookStartResult(true, _mouseHook != 0, mouseError);
    }

    private void PrepareHotPath()
    {
        WindowsScanCodeMapper.WarmUp();
        RuntimeHelpers.PrepareDelegate(_keyboardCallback);
        RuntimeHelpers.PrepareDelegate(_mouseCallback);
        _ = Marshal.SizeOf<NativeMethods.KeyboardLowLevelHookData>();
        _ = Marshal.SizeOf<NativeMethods.MouseLowLevelHookData>();
        _ = Stopwatch.GetTimestamp();
    }

    private void ReinstallHooksOnCurrentThread()
    {
        Volatile.Write(ref _acceptingEvents, 0);
        UninstallHooks();
        _repeatTracker.Reset();
        EnqueueReset();
        var result = InstallHooks();
        if (!result.Started)
        {
            Volatile.Write(
                ref _lastCallbackError,
                new System.ComponentModel.Win32Exception(result.ErrorCode));
            return;
        }

        Volatile.Write(ref _acceptingEvents, 1);
    }

    private void UninstallHooks()
    {
        if (_mouseHook != 0)
        {
            _ = NativeMethods.UnhookWindowsHookEx(_mouseHook);
            _mouseHook = 0;
        }

        if (_keyboardHook != 0)
        {
            _ = NativeMethods.UnhookWindowsHookEx(_keyboardHook);
            _keyboardHook = 0;
        }
    }

    private nint KeyboardHookCallback(int code, nuint wParam, nint lParam)
    {
        if (code < NativeMethods.HcAction)
        {
            return NativeMethods.CallNextHookEx(_keyboardHook, code, wParam, lParam);
        }

        var callbackTimestamp = Stopwatch.GetTimestamp();
        Volatile.Write(ref _lastHookCallbackTimestamp, callbackTimestamp);
        try
        {
            if (Volatile.Read(ref _acceptingEvents) != 0)
            {
                var native = Marshal.PtrToStructure<NativeMethods.KeyboardLowLevelHookData>(lParam);
                var sequence = _nextSequence + 1;
                if (WindowsHookEventDecoder.TryDecodeKeyboard(
                    (uint)wParam,
                    native.VirtualKey,
                    native.ScanCode,
                    native.Flags,
                    native.ExtraInfo,
                    native.Time,
                    callbackTimestamp,
                    sequence,
                    SyntheticInputSentinel,
                    _repeatTracker,
                    out var input))
                {
                    _nextSequence = sequence;
                    _queue.TryWrite(RawWindowsInputEvent.FromKeyboard(input));
                }
            }
        }
        catch (Exception exception)
        {
            Volatile.Write(ref _lastCallbackError, exception);
        }

        return NativeMethods.CallNextHookEx(_keyboardHook, code, wParam, lParam);
    }

    private nint MouseHookCallback(int code, nuint wParam, nint lParam)
    {
        if (code < NativeMethods.HcAction)
        {
            return NativeMethods.CallNextHookEx(_mouseHook, code, wParam, lParam);
        }

        var callbackTimestamp = Stopwatch.GetTimestamp();
        Volatile.Write(ref _lastHookCallbackTimestamp, callbackTimestamp);
        try
        {
            if (Volatile.Read(ref _acceptingEvents) != 0
                && WindowsHookEventDecoder.IsPointerButtonMessage((uint)wParam))
            {
                var native = Marshal.PtrToStructure<NativeMethods.MouseLowLevelHookData>(lParam);
                var sequence = _nextSequence + 1;
                if (WindowsHookEventDecoder.TryDecodePointer(
                    (uint)wParam,
                    native.MouseData,
                    native.Flags,
                    native.ExtraInfo,
                    native.Time,
                    callbackTimestamp,
                    sequence,
                    SyntheticInputSentinel,
                    out var input))
                {
                    _nextSequence = sequence;
                    _queue.TryWrite(RawWindowsInputEvent.FromMouse(input));
                }
            }
        }
        catch (Exception exception)
        {
            Volatile.Write(ref _lastCallbackError, exception);
        }

        return NativeMethods.CallNextHookEx(_mouseHook, code, wParam, lParam);
    }

    private void EnqueueReset()
    {
        var sequence = ++_nextSequence;
        _queue.TryWrite(RawWindowsInputEvent.Reset(sequence));
    }

    private async Task ConsumeQueueAsync()
    {
        ulong lastSequence = 0;
        var reader = _queue.Reader;

        while (true)
        {
            while (reader.TryRead(out var input))
            {
                if (lastSequence != 0 && input.Sequence != lastSequence + 1)
                {
                    _normalizer.Reset();
                }

                lastSequence = input.Sequence;
                await ConsumeRawEventAsync(input).ConfigureAwait(false);
            }

            if (reader.Completion.IsCompleted)
            {
                break;
            }

            if (_normalizer.HasPendingEvent)
            {
                var remainingTicks = _normalizer.PendingDeadlineTimestamp - Stopwatch.GetTimestamp();
                if (remainingTicks <= 0)
                {
                    await FlushPendingKeyboardEventAsync().ConfigureAwait(false);
                    continue;
                }

                var remaining = TimeSpan.FromSeconds(
                    (double)remainingTicks / Stopwatch.Frequency);
                var dataAvailable = reader.WaitToReadAsync().AsTask();
                var deadline = Task.Delay(remaining, _timeProvider);
                if (await Task.WhenAny(dataAvailable, deadline).ConfigureAwait(false) == deadline)
                {
                    await FlushPendingKeyboardEventAsync().ConfigureAwait(false);
                }

                continue;
            }

            if (!await reader.WaitToReadAsync().ConfigureAwait(false))
            {
                break;
            }
        }

        await FlushPendingKeyboardEventAsync().ConfigureAwait(false);
    }

    private async ValueTask ConsumeRawEventAsync(RawWindowsInputEvent input)
    {
        if (input.Kind == WindowsRawInputKind.Reset)
        {
            _normalizer.Reset();
            return;
        }

        if (input.Kind == WindowsRawInputKind.Mouse)
        {
            await FlushPendingKeyboardEventAsync().ConfigureAwait(false);
            var pointer = input.Mouse;
            await DeliverAsync(WindowsInputEvent.FromMouse(
                new WindowsPointerInputEvent(
                    pointer.Button,
                    pointer.Phase,
                    pointer.Origin,
                    _timeProvider.GetUtcNow(),
                    pointer.Sequence),
                _foregroundApplications.Current)).ConfigureAwait(false);
            return;
        }

        var timestamp = _timeProvider.GetUtcNow();
        var normalized = _normalizer.Process(input.Keyboard, timestamp);
        if (normalized.Count >= 1)
        {
            await DeliverAsync(WindowsInputEvent.FromKeyboard(
                normalized.First,
                _foregroundApplications.Current)).ConfigureAwait(false);
        }

        if (normalized.Count >= 2)
        {
            await DeliverAsync(WindowsInputEvent.FromKeyboard(
                normalized.Second,
                _foregroundApplications.Current)).ConfigureAwait(false);
        }
    }

    private async ValueTask FlushPendingKeyboardEventAsync()
    {
        if (_normalizer.FlushPending(_timeProvider.GetUtcNow()) is not { } pending)
        {
            return;
        }

        await DeliverAsync(WindowsInputEvent.FromKeyboard(
            pending,
            _foregroundApplications.Current)).ConfigureAwait(false);
    }

    private async ValueTask DeliverAsync(WindowsInputEvent input)
    {
        try
        {
            await _sink.OnInputAsync(input, CancellationToken.None).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            Volatile.Write(ref _lastConsumerError, exception);
        }
    }

}
