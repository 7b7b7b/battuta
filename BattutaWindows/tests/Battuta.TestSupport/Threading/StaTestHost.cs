using System.Collections.Concurrent;
using System.Runtime.ExceptionServices;
using System.Runtime.Versioning;

namespace Battuta.TestSupport.Threading;

/// <summary>
/// Runs a delegate on an isolated Windows STA thread. Async continuations are
/// pumped on the same thread so tests do not silently resume on an MTA worker.
/// </summary>
[SupportedOSPlatform("windows")]
public static class StaTestHost
{
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(30);

    public static void Run(Action action, TimeSpan? timeout = null)
    {
        ArgumentNullException.ThrowIfNull(action);
        RunAsync(
            () =>
            {
                action();
                return Task.CompletedTask;
            },
            timeout).GetAwaiter().GetResult();
    }

    public static T Run<T>(Func<T> action, TimeSpan? timeout = null)
    {
        ArgumentNullException.ThrowIfNull(action);
        return RunAsync(() => Task.FromResult(action()), timeout).GetAwaiter().GetResult();
    }

    public static Task RunAsync(Func<Task> action, TimeSpan? timeout = null)
    {
        ArgumentNullException.ThrowIfNull(action);
        return RunAsync(
            async () =>
            {
                await action();
                return true;
            },
            timeout);
    }

    public static Task<T> RunAsync<T>(Func<Task<T>> action, TimeSpan? timeout = null)
    {
        ArgumentNullException.ThrowIfNull(action);
        EnsureWindows();

        var effectiveTimeout = timeout ?? DefaultTimeout;
        if (effectiveTimeout <= TimeSpan.Zero && effectiveTimeout != Timeout.InfiniteTimeSpan)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }

        var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() => ExecuteOnSta(action, completion))
        {
            IsBackground = true,
            Name = $"Battuta.STA.Test.{Guid.NewGuid():N}",
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();

        return completion.Task.WaitAsync(effectiveTimeout);
    }

    private static void ExecuteOnSta<T>(
        Func<Task<T>> action,
        TaskCompletionSource<T> completion)
    {
        using var context = new PumpSynchronizationContext(Environment.CurrentManagedThreadId);
        var previousContext = SynchronizationContext.Current;
        SynchronizationContext.SetSynchronizationContext(context);

        try
        {
            Task<T> operation;
            try
            {
                operation = action()
                    ?? throw new InvalidOperationException("The STA test delegate returned a null task.");
            }
            catch (Exception error)
            {
                completion.TrySetException(error);
                return;
            }

            _ = operation.ContinueWith(
                static (_, state) => ((PumpSynchronizationContext)state!).Complete(),
                context,
                CancellationToken.None,
                TaskContinuationOptions.ExecuteSynchronously,
                TaskScheduler.Default);

            context.RunOnCurrentThread();
            completion.TrySetResult(operation.GetAwaiter().GetResult());
        }
        catch (OperationCanceledException error)
        {
            completion.TrySetCanceled(error.CancellationToken);
        }
        catch (Exception error)
        {
            completion.TrySetException(error);
        }
        finally
        {
            context.Complete();
            SynchronizationContext.SetSynchronizationContext(previousContext);
        }
    }

    private static void EnsureWindows()
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("STA UI tests require Windows.");
        }
    }

    private sealed class PumpSynchronizationContext : SynchronizationContext, IDisposable
    {
        private readonly BlockingCollection<WorkItem> queue = new();
        private readonly int ownerThreadId;

        public PumpSynchronizationContext(int ownerThreadId)
        {
            this.ownerThreadId = ownerThreadId;
        }

        public override void Post(SendOrPostCallback callback, object? state)
        {
            ArgumentNullException.ThrowIfNull(callback);
            if (!queue.IsAddingCompleted)
            {
                try
                {
                    queue.Add(new WorkItem(callback, state));
                }
                catch (InvalidOperationException) when (queue.IsAddingCompleted)
                {
                    // Completion raced with a late, irrelevant continuation.
                }
            }
        }

        public override void Send(SendOrPostCallback callback, object? state)
        {
            ArgumentNullException.ThrowIfNull(callback);
            if (Environment.CurrentManagedThreadId == ownerThreadId)
            {
                callback(state);
                return;
            }

            using var signal = new ManualResetEventSlim();
            ExceptionDispatchInfo? capturedError = null;
            var workItem = new WorkItem(
                value =>
                {
                    try
                    {
                        callback(value);
                    }
                    catch (Exception error)
                    {
                        capturedError = ExceptionDispatchInfo.Capture(error);
                    }
                    finally
                    {
                        signal.Set();
                    }
                },
                state);
            try
            {
                queue.Add(workItem);
            }
            catch (InvalidOperationException error) when (queue.IsAddingCompleted)
            {
                throw new InvalidOperationException(
                    "The STA synchronization context has already completed.",
                    error);
            }

            signal.Wait();
            capturedError?.Throw();
        }

        public void RunOnCurrentThread()
        {
            foreach (var workItem in queue.GetConsumingEnumerable())
            {
                workItem.Callback(workItem.State);
            }
        }

        public void Complete()
        {
            if (!queue.IsAddingCompleted)
            {
                queue.CompleteAdding();
            }
        }

        public void Dispose()
        {
            Complete();
            queue.Dispose();
        }

        private readonly record struct WorkItem(SendOrPostCallback Callback, object? State);
    }
}
