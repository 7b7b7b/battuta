using System.Collections.Concurrent;
using Battuta.Windows.Activation;

namespace Battuta.Windows.Tests.Platform.Activation;

public sealed class ActivationTests
{
    [Theory]
    [InlineData("--startup", ActivationKind.Startup)]
    [InlineData("--show-stats", ActivationKind.ShowStatistics)]
    [InlineData("--show-diy", ActivationKind.ShowDiyEditor)]
    public void ArgumentsMapToExpectedActivation(string argument, ActivationKind expected)
    {
        var request = ActivationRequest.FromArguments([argument]);
        Assert.Equal(expected, request.Kind);
    }

    [Fact]
    public async Task SecondaryInstanceForwardsActivationToPrimary()
    {
        var applicationId = "BattutaTest" + Guid.NewGuid().ToString("N");
        var firstRequest = new ActivationRequest(ActivationKind.Start, []);
        var primaryResult = await SingleInstanceService.AcquireAsync(
            firstRequest,
            applicationId,
            deliveryTimeout: TimeSpan.FromSeconds(3));
        Assert.True(primaryResult.IsPrimary);
        Assert.NotNull(primaryResult.PrimaryInstance);
        await using var primary = primaryResult.PrimaryInstance!;

        var received = new TaskCompletionSource<ActivationRequest>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        primary.ActivationReceived += (_, request) => received.TrySetResult(request);
        var secondaryRequest = new ActivationRequest(ActivationKind.ShowStatistics, ["--show-stats"]);

        var secondaryResult = await SingleInstanceService.AcquireAsync(
            secondaryRequest,
            applicationId,
            deliveryTimeout: TimeSpan.FromSeconds(3));

        Assert.False(secondaryResult.IsPrimary);
        Assert.True(secondaryResult.ActivationDelivered);
        var forwarded = await received.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Assert.Equal(ActivationKind.ShowStatistics, forwarded.Kind);
    }

    [Fact]
    public async Task ActivationsReceivedBeforeSubscriptionAreDeliveredInOrder()
    {
        var applicationId = "BattutaTest" + Guid.NewGuid().ToString("N");
        var primaryResult = await SingleInstanceService.AcquireAsync(
            new ActivationRequest(ActivationKind.Start, []),
            applicationId,
            deliveryTimeout: TimeSpan.FromSeconds(3));
        Assert.True(primaryResult.IsPrimary);
        await using var primary = Assert.IsType<SingleInstanceService>(
            primaryResult.PrimaryInstance);

        var first = new ActivationRequest(
            ActivationKind.ShowStatistics,
            ["--show-stats", "first"]);
        var second = new ActivationRequest(
            ActivationKind.ShowDiyEditor,
            ["--show-diy", "second"]);

        var firstDelivery = await SingleInstanceService.AcquireAsync(
            first,
            applicationId,
            deliveryTimeout: TimeSpan.FromSeconds(3));
        Assert.False(firstDelivery.IsPrimary);
        Assert.True(firstDelivery.ActivationDelivered);

        // Connecting the second client requires the single pipe server to finish
        // dispatching the first request and create its next pipe instance. This
        // makes the first activation deterministically precede subscription.
        var secondDelivery = await SingleInstanceService.AcquireAsync(
            second,
            applicationId,
            deliveryTimeout: TimeSpan.FromSeconds(3));
        Assert.False(secondDelivery.IsPrimary);
        Assert.True(secondDelivery.ActivationDelivered);

        var received = new List<ActivationRequest>();
        var completed = new TaskCompletionSource<IReadOnlyList<ActivationRequest>>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        primary.ActivationReceived += (_, activation) =>
        {
            lock (received)
            {
                received.Add(activation);
                if (received.Count == 2)
                {
                    completed.TrySetResult(received.ToArray());
                }
            }
        };

        var ordered = await completed.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Assert.Collection(
            ordered,
            activation =>
            {
                Assert.Equal(first.Kind, activation.Kind);
                Assert.Equal(first.Arguments.ToArray(), activation.Arguments.ToArray());
            },
            activation =>
            {
                Assert.Equal(second.Kind, activation.Kind);
                Assert.Equal(second.Arguments.ToArray(), activation.Arguments.ToArray());
            });
    }

    [Fact]
    public async Task ActivationDrainUsesConfiguredSynchronizationContext()
    {
        using var callbackContext = new QueuedSynchronizationContext();
        var applicationId = "BattutaTest" + Guid.NewGuid().ToString("N");
        var primaryResult = await SingleInstanceService.AcquireAsync(
            new ActivationRequest(ActivationKind.Start, []),
            applicationId,
            deliveryTimeout: TimeSpan.FromSeconds(3),
            callbackContext: callbackContext);
        Assert.True(primaryResult.IsPrimary);
        await using var primary = Assert.IsType<SingleInstanceService>(
            primaryResult.PrimaryInstance);

        var received = new TaskCompletionSource<bool>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        primary.ActivationReceived += (_, _) =>
            received.TrySetResult(callbackContext.IsExecutingCallback);

        var delivery = await SingleInstanceService.AcquireAsync(
            new ActivationRequest(ActivationKind.ShowStatistics, ["--show-stats"]),
            applicationId,
            deliveryTimeout: TimeSpan.FromSeconds(3));
        Assert.False(delivery.IsPrimary);
        Assert.True(delivery.ActivationDelivered);

        Assert.False(received.Task.IsCompleted);
        await callbackContext.RunNextAsync(TimeSpan.FromSeconds(3));
        Assert.True(await received.Task.WaitAsync(TimeSpan.FromSeconds(3)));
    }

    private sealed class QueuedSynchronizationContext : SynchronizationContext, IDisposable
    {
        private readonly ConcurrentQueue<(SendOrPostCallback Callback, object? State)> callbacks = new();
        private readonly SemaphoreSlim callbackAvailable = new(0);

        public bool IsExecutingCallback { get; private set; }

        public override void Post(SendOrPostCallback callback, object? state)
        {
            ArgumentNullException.ThrowIfNull(callback);
            callbacks.Enqueue((callback, state));
            callbackAvailable.Release();
        }

        public async Task RunNextAsync(TimeSpan timeout)
        {
            if (!await callbackAvailable.WaitAsync(timeout))
            {
                throw new TimeoutException("No synchronization-context callback was posted.");
            }

            if (!callbacks.TryDequeue(out var workItem))
            {
                throw new InvalidOperationException("A callback signal was posted without a callback.");
            }

            IsExecutingCallback = true;
            try
            {
                workItem.Callback(workItem.State);
            }
            finally
            {
                IsExecutingCallback = false;
            }
        }

        public void Dispose() => callbackAvailable.Dispose();
    }
}
