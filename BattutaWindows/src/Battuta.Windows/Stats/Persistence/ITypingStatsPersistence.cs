using Battuta.Windows.Stats.Models;

namespace Battuta.Windows.Stats.Persistence;

public interface ITypingStatsPersistence
{
    Task RecordAsync(TypingStatsWriteBatch batch, CancellationToken cancellationToken = default);

    Task<TypingStatsSnapshot> LoadSnapshotAsync(
        TypingTimelineRange timelineRange = TypingTimelineRange.OneHour,
        CancellationToken cancellationToken = default);

    Task<TypingRangeReportSnapshot> LoadReportAsync(
        TypingDateRange range,
        TypingDateRange? comparisonRange = null,
        CancellationToken cancellationToken = default);

    Task ClearAllAsync(CancellationToken cancellationToken = default);
}

public enum TypingStatsStoreErrorKind
{
    CannotCreateDirectory,
    CannotOpen,
    IncompatibleSchema,
    Busy,
    Corrupt,
    QueryFailed,
}

public sealed class TypingStatsStoreException : Exception
{
    public TypingStatsStoreException(
        TypingStatsStoreErrorKind kind,
        string message,
        Exception? innerException = null)
        : base(message, innerException)
    {
        Kind = kind;
    }

    public TypingStatsStoreErrorKind Kind { get; }
}
