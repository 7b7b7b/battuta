using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

namespace Battuta.Windows.Activation;

public sealed record SingleInstanceAcquireResult(
    bool IsPrimary,
    SingleInstanceService? PrimaryInstance,
    bool ActivationDelivered)
{
    public static SingleInstanceAcquireResult Primary(SingleInstanceService service) =>
        new(true, service, false);

    public static SingleInstanceAcquireResult Secondary(bool delivered) =>
        new(false, null, delivered);
}

/// <summary>
/// Per-user, per-interactive-session single-instance coordination. Secondary
/// processes forward a small JSON activation message and then terminate before
/// starting hooks, audio, or SQLite.
/// </summary>
public sealed class SingleInstanceService : IAsyncDisposable, IDisposable
{
    private const int MaxMessageBytes = 64 * 1024;
    private const int MaxPendingActivations = 32;
    private readonly Mutex _mutex;
    private readonly string _pipeName;
    private readonly CancellationTokenSource _serverCancellation = new();
    private readonly JsonSerializerOptions _serializerOptions = new(JsonSerializerDefaults.Web);
    private readonly SynchronizationContext? _callbackContext;
    private readonly int _ownershipThreadId;
    private readonly object _activationLock = new();
    private readonly Queue<ActivationRequest> _pendingActivations = new();
    private EventHandler<ActivationRequest>? _activationReceived;
    private Task? _serverTask;
    private bool _activationDrainScheduled;
    private bool _ownsMutex;
    private bool _disposed;

    private SingleInstanceService(
        Mutex mutex,
        bool ownsMutex,
        string pipeName,
        SynchronizationContext? callbackContext)
    {
        _mutex = mutex;
        _ownsMutex = ownsMutex;
        _pipeName = pipeName;
        _callbackContext = callbackContext;
        _ownershipThreadId = Environment.CurrentManagedThreadId;
    }

    public event EventHandler<ActivationRequest>? ActivationReceived
    {
        add
        {
            ArgumentNullException.ThrowIfNull(value);
            var shouldScheduleDrain = false;
            lock (_activationLock)
            {
                ObjectDisposedException.ThrowIf(_disposed, this);
                _activationReceived += value;
                shouldScheduleDrain = TryScheduleActivationDrainLocked();
            }

            if (shouldScheduleDrain)
            {
                ScheduleActivationDrain();
            }
        }
        remove
        {
            lock (_activationLock)
            {
                _activationReceived -= value;
            }
        }
    }

    public static async Task<SingleInstanceAcquireResult> AcquireAsync(
        ActivationRequest activation,
        string applicationId = "Battuta",
        TimeSpan? deliveryTimeout = null,
        SynchronizationContext? callbackContext = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(activation);
        ArgumentException.ThrowIfNullOrWhiteSpace(applicationId);

        var suffix = CreateScopeSuffix(applicationId);
        var mutex = new Mutex(initiallyOwned: true, $"Local\\{applicationId}-{suffix}", out var createdNew);
        if (createdNew)
        {
            var primary = new SingleInstanceService(
                mutex,
                ownsMutex: true,
                pipeName: $"{applicationId}.{suffix}",
                callbackContext);
            primary._serverTask = primary.RunServerAsync(primary._serverCancellation.Token);
            return SingleInstanceAcquireResult.Primary(primary);
        }

        var secondary = new SingleInstanceService(
            mutex,
            ownsMutex: false,
            pipeName: $"{applicationId}.{suffix}",
            callbackContext: null);
        try
        {
            var delivered = await secondary.SendActivationAsync(
                activation,
                deliveryTimeout ?? TimeSpan.FromSeconds(2),
                cancellationToken).ConfigureAwait(false);
            return SingleInstanceAcquireResult.Secondary(delivered);
        }
        finally
        {
            secondary.Dispose();
        }
    }

    public async Task<bool> SendActivationAsync(
        ActivationRequest activation,
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(activation);
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(timeout, TimeSpan.Zero);

        var payload = JsonSerializer.SerializeToUtf8Bytes(activation, _serializerOptions);
        if (payload.Length > MaxMessageBytes)
        {
            throw new InvalidOperationException("Activation request is too large.");
        }

        using var timeoutCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutCancellation.CancelAfter(timeout);
        var deadline = Stopwatch.StartNew();

        while (deadline.Elapsed < timeout)
        {
            timeoutCancellation.Token.ThrowIfCancellationRequested();
            try
            {
                await using var client = new NamedPipeClientStream(
                    ".",
                    _pipeName,
                    PipeDirection.Out,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                var remaining = timeout - deadline.Elapsed;
                await client.ConnectAsync(remaining, timeoutCancellation.Token).ConfigureAwait(false);
                await WriteMessageAsync(client, payload, timeoutCancellation.Token).ConfigureAwait(false);
                return true;
            }
            catch (TimeoutException)
            {
                return false;
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                return false;
            }
            catch (IOException) when (deadline.Elapsed < timeout)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(75), timeoutCancellation.Token)
                    .ConfigureAwait(false);
            }
        }

        return false;
    }

    public async ValueTask DisposeAsync()
    {
        DisposeCore();
        if (_serverTask is not null)
        {
            try
            {
                await _serverTask.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
        }

        _serverCancellation.Dispose();
        _mutex.Dispose();
        GC.SuppressFinalize(this);
    }

    public void Dispose()
    {
        DisposeCore();
        _serverCancellation.Dispose();
        _mutex.Dispose();
        GC.SuppressFinalize(this);
    }

    private void DisposeCore()
    {
        lock (_activationLock)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            _activationReceived = null;
            _pendingActivations.Clear();
        }

        _serverCancellation.Cancel();
        if (_ownsMutex && Environment.CurrentManagedThreadId == _ownershipThreadId)
        {
            try
            {
                _mutex.ReleaseMutex();
            }
            catch (ApplicationException)
            {
            }

            _ownsMutex = false;
        }
    }

    private async Task RunServerAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await using var server = new NamedPipeServerStream(
                    _pipeName,
                    PipeDirection.In,
                    maxNumberOfServerInstances: 1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await server.WaitForConnectionAsync(cancellationToken).ConfigureAwait(false);
                var request = await ReadMessageAsync(server, cancellationToken).ConfigureAwait(false);
                if (request is not null)
                {
                    QueueActivation(request);
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (IOException)
            {
                if (!cancellationToken.IsCancellationRequested)
                {
                    await Task.Delay(100, cancellationToken).ConfigureAwait(false);
                }
            }
            catch (JsonException)
            {
                // Ignore malformed local messages and continue accepting valid
                // activations. The pipe is restricted to the current user.
            }
        }
    }

    private async Task<ActivationRequest?> ReadMessageAsync(
        Stream stream,
        CancellationToken cancellationToken)
    {
        var lengthBytes = new byte[sizeof(int)];
        if (!await ReadExactlyOrEndAsync(stream, lengthBytes, cancellationToken).ConfigureAwait(false))
        {
            return null;
        }

        var length = BitConverter.ToInt32(lengthBytes);
        if (length is <= 0 or > MaxMessageBytes)
        {
            throw new InvalidDataException("Activation message length is invalid.");
        }

        var payload = new byte[length];
        if (!await ReadExactlyOrEndAsync(stream, payload, cancellationToken).ConfigureAwait(false))
        {
            return null;
        }

        return JsonSerializer.Deserialize<ActivationRequest>(payload, _serializerOptions);
    }

    private static async Task WriteMessageAsync(
        Stream stream,
        byte[] payload,
        CancellationToken cancellationToken)
    {
        await stream.WriteAsync(BitConverter.GetBytes(payload.Length), cancellationToken).ConfigureAwait(false);
        await stream.WriteAsync(payload, cancellationToken).ConfigureAwait(false);
        await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
    }

    private static async Task<bool> ReadExactlyOrEndAsync(
        Stream stream,
        Memory<byte> buffer,
        CancellationToken cancellationToken)
    {
        var offset = 0;
        while (offset < buffer.Length)
        {
            var read = await stream.ReadAsync(buffer[offset..], cancellationToken).ConfigureAwait(false);
            if (read == 0)
            {
                return false;
            }

            offset += read;
        }

        return true;
    }

    private void QueueActivation(ActivationRequest request)
    {
        var shouldScheduleDrain = false;
        lock (_activationLock)
        {
            if (_disposed)
            {
                return;
            }

            if (_pendingActivations.Count == MaxPendingActivations)
            {
                // Keep the newest user intents while preventing a secondary-process
                // flood during startup from growing memory without bound.
                _pendingActivations.Dequeue();
            }

            _pendingActivations.Enqueue(request);
            shouldScheduleDrain = TryScheduleActivationDrainLocked();
        }

        if (shouldScheduleDrain)
        {
            ScheduleActivationDrain();
        }
    }

    private bool TryScheduleActivationDrainLocked()
    {
        if (_disposed
            || _activationDrainScheduled
            || _activationReceived is null
            || _pendingActivations.Count == 0)
        {
            return false;
        }

        _activationDrainScheduled = true;
        return true;
    }

    private void ScheduleActivationDrain()
    {
        if (_callbackContext is not null)
        {
            _callbackContext.Post(
                static state => ((SingleInstanceService)state!).DrainPendingActivations(),
                this);
            return;
        }

        ThreadPool.UnsafeQueueUserWorkItem(
            static service => service.DrainPendingActivations(),
            this,
            preferLocal: false);
    }

    private void DrainPendingActivations()
    {
        try
        {
            while (true)
            {
                EventHandler<ActivationRequest> handler;
                ActivationRequest activation;
                lock (_activationLock)
                {
                    if (_disposed
                        || _activationReceived is not { } currentHandler
                        || _pendingActivations.Count == 0)
                    {
                        return;
                    }

                    handler = currentHandler;
                    activation = _pendingActivations.Dequeue();
                }

                handler.Invoke(this, activation);
            }
        }
        finally
        {
            var shouldScheduleDrain = false;
            lock (_activationLock)
            {
                _activationDrainScheduled = false;
                shouldScheduleDrain = TryScheduleActivationDrainLocked();
            }

            if (shouldScheduleDrain)
            {
                ScheduleActivationDrain();
            }
        }
    }

    private static string CreateScopeSuffix(string applicationId)
    {
        string userIdentity;
        try
        {
            userIdentity = WindowsIdentity.GetCurrent().User?.Value
                ?? Environment.UserName;
        }
        catch (PlatformNotSupportedException)
        {
            userIdentity = Environment.UserName;
        }

        var sessionId = OperatingSystem.IsWindows()
            ? Process.GetCurrentProcess().SessionId
            : 0;
        var input = Encoding.UTF8.GetBytes($"{applicationId}|{userIdentity}|{sessionId}");
        var hash = Convert.ToHexString(SHA256.HashData(input));
        return hash[..16];
    }
}
