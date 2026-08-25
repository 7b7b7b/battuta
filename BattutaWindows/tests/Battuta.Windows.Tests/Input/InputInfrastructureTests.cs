using Battuta.Windows.Input;

namespace Battuta.Windows.Tests.Input;

public sealed class InputInfrastructureTests
{
    [Fact]
    public async Task DedicatedHookMessageThreadStartsAndStopsCleanly()
    {
        if (!Environment.UserInteractive)
        {
            return;
        }

        var sink = new DelegateWindowsInputEventSink(
            static (_, _) => ValueTask.CompletedTask);
        await using var service = new Win32InputHookService(sink);
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));

        var result = await service.StartAsync(timeout.Token);
        Assert.True(result.KeyboardHookStarted);
        Assert.True(service.IsRunning);

        await service.StopAsync(timeout.Token);
        Assert.False(service.IsRunning);
    }

    [Fact]
    public void BoundedQueueDropsOldestWithoutBlockingProducer()
    {
        var queue = new BoundedWindowsInputEventBuffer(2);

        Assert.True(queue.TryWrite(RawWindowsInputEvent.Reset(1)));
        Assert.True(queue.TryWrite(RawWindowsInputEvent.Reset(2)));
        Assert.True(queue.TryWrite(RawWindowsInputEvent.Reset(3)));

        Assert.Equal(1, queue.DroppedCount);
        Assert.True(queue.Reader.TryRead(out var second));
        Assert.True(queue.Reader.TryRead(out var third));
        Assert.Equal((ulong)2, second.Sequence);
        Assert.Equal((ulong)3, third.Sequence);
    }

    [Fact]
    public void ForegroundCacheRejectsLateResolutionFromOlderWindow()
    {
        var cache = new ForegroundApplicationCache();
        var newer = new ForegroundApplicationSnapshot(2, "process:new", "New", "new");
        var older = new ForegroundApplicationSnapshot(1, "process:old", "Old", "old");

        Assert.True(cache.TryPublish(2, newer));
        Assert.False(cache.TryPublish(1, older));

        Assert.Equal(newer, cache.Current);
        Assert.Equal(2, cache.Generation);
    }

    [Fact]
    public void ForegroundCacheNeverRequiresAWindowTitle()
    {
        var cache = new ForegroundApplicationCache();
        var snapshot = new ForegroundApplicationSnapshot(
            42,
            "process:code",
            "Code",
            "code");

        Assert.True(cache.TryPublish(1, snapshot));
        Assert.Equal("process:code", cache.Current.ProcessKey);
        Assert.Equal("code", cache.Current.ProcessName);
    }
}
