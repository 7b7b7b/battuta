using System.Threading.Channels;

namespace Battuta.Windows.Input;

/// <summary>
/// A non-blocking single-producer/single-consumer queue. When overloaded it keeps the
/// newest input, which is preferable to playing stale audio after a long backlog.
/// </summary>
public sealed class BoundedWindowsInputEventBuffer
{
    private readonly Channel<RawWindowsInputEvent> _channel;
    private long _droppedCount;

    public BoundedWindowsInputEventBuffer(int capacity)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(capacity);

        _channel = Channel.CreateBounded<RawWindowsInputEvent>(
            new BoundedChannelOptions(capacity)
            {
                SingleWriter = true,
                SingleReader = true,
                AllowSynchronousContinuations = false,
                FullMode = BoundedChannelFullMode.DropOldest,
            },
            _ => Interlocked.Increment(ref _droppedCount));
    }

    public ChannelReader<RawWindowsInputEvent> Reader => _channel.Reader;

    public long DroppedCount => Interlocked.Read(ref _droppedCount);

    public bool TryWrite(RawWindowsInputEvent input) => _channel.Writer.TryWrite(input);

    public bool TryComplete(Exception? error = null) => _channel.Writer.TryComplete(error);
}
