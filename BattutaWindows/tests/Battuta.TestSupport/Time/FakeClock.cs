namespace Battuta.TestSupport.Time;

/// <summary>
/// A deterministic, thread-safe wall clock for tests that normally depend on
/// <see cref="DateTimeOffset.Now"/> or <see cref="DateTimeOffset.UtcNow"/>.
/// </summary>
public sealed class FakeClock
{
    private readonly object gate = new();
    private DateTimeOffset now;

    public FakeClock(DateTimeOffset initialValue)
    {
        now = initialValue;
    }

    /// <summary>Gets the current value, preserving its configured UTC offset.</summary>
    public DateTimeOffset Now
    {
        get
        {
            lock (gate)
            {
                return now;
            }
        }
    }

    /// <summary>Gets the current value normalized to UTC.</summary>
    public DateTimeOffset UtcNow => Now.ToUniversalTime();

    /// <summary>Returns a provider suitable for constructor injection.</summary>
    public Func<DateTimeOffset> AsProvider() => ReadNow;

    /// <summary>Replaces the clock value and returns the new value.</summary>
    public DateTimeOffset Set(DateTimeOffset value)
    {
        lock (gate)
        {
            now = value;
            return now;
        }
    }

    /// <summary>Moves the clock forward and returns the new value.</summary>
    public DateTimeOffset Advance(TimeSpan elapsed)
    {
        if (elapsed < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(
                nameof(elapsed),
                elapsed,
                "Use Set when a test intentionally needs to move time backwards.");
        }

        lock (gate)
        {
            now = now.Add(elapsed);
            return now;
        }
    }

    private DateTimeOffset ReadNow() => Now;
}
