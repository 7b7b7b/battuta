using System.Collections.ObjectModel;
using Battuta.Core.Input;

namespace Battuta.TestSupport.Fixtures;

public sealed record StatsApplicationFixture(
    string ProcessKey,
    string DisplayName,
    string ProcessName,
    string? ApplicationUserModelId = null);

public sealed record CharacterAggregateFixture(
    long SecondStartUtc,
    DateOnly LocalDate,
    int LocalHour,
    StatsApplicationFixture Application,
    long Count);

public sealed record PhysicalKeyAggregateFixture(
    DateOnly LocalDate,
    PhysicalKeyId PhysicalKeyId,
    long Count);

public sealed record StatsAggregateFixture(
    DateTimeOffset Now,
    IReadOnlyList<CharacterAggregateFixture> CharacterAggregates,
    IReadOnlyList<PhysicalKeyAggregateFixture> KeyAggregates);

public sealed record StatsInputEventFixture(
    DateTimeOffset Timestamp,
    PhysicalKeyId PhysicalKeyId,
    StatsApplicationFixture Application,
    bool IsRepeat,
    bool IsShortcutModified);

public sealed record StatsDailyFixture(
    DateOnly Date,
    long CharacterCount,
    long PeakCps,
    long ActiveSeconds,
    string? TopApplicationProcessKey,
    IReadOnlyDictionary<string, long> ApplicationCounts);

public sealed record StatsApplicationComparisonFixture(
    StatsApplicationFixture Application,
    long CurrentCharacterCount,
    long PreviousCharacterCount);

public sealed record StatsUiHistoryFixture(
    DateTimeOffset GeneratedAt,
    DateOnly StartDate,
    DateOnly EndDate,
    int CurrentPeriodDayCount,
    IReadOnlyList<StatsApplicationFixture> Applications,
    IReadOnlyList<StatsDailyFixture> Days,
    IReadOnlyList<StatsApplicationComparisonFixture> ApplicationComparisons);

/// <summary>Deterministic aggregate and UI data shaped after the macOS regression harness.</summary>
public static class StatsFixtureFactory
{
    public static StatsAggregateFixture CreateTwoDayAggregateFixture(
        DateTimeOffset now,
        TimeZoneInfo? timeZone = null)
    {
        var zone = timeZone ?? TimeZoneInfo.Utc;
        var localNow = TimeZoneInfo.ConvertTime(now, zone);
        var tenSecondsPriorInstant = now.AddSeconds(-10);
        var localTenSecondsPrior = TimeZoneInfo.ConvertTime(tenSecondsPriorInstant, zone);
        var priorInstant = now.AddDays(-1);
        var localPrior = TimeZoneInfo.ConvertTime(priorInstant, zone);
        var today = DateOnly.FromDateTime(localNow.DateTime);
        var tenSecondsPriorDate = DateOnly.FromDateTime(localTenSecondsPrior.DateTime);
        var yesterday = DateOnly.FromDateTime(localPrior.DateTime);
        var appOne = CreateApplication(1);
        var appTwo = CreateApplication(2);

        CharacterAggregateFixture[] characters =
        [
            new(now.ToUnixTimeSeconds(), today, localNow.Hour, appOne, 3),
            new(now.ToUnixTimeSeconds(), today, localNow.Hour, appTwo, 2),
            new(
                tenSecondsPriorInstant.ToUnixTimeSeconds(),
                tenSecondsPriorDate,
                localTenSecondsPrior.Hour,
                appOne,
                4),
            new(priorInstant.ToUnixTimeSeconds(), yesterday, localPrior.Hour, appTwo, 12),
        ];

        PhysicalKeyAggregateFixture[] keys =
        [
            new(today, PhysicalKeys.KeyA, 5),
            new(today, PhysicalKeys.LeftShift, 2),
            new(yesterday, PhysicalKeys.KeyA, 3),
        ];

        return new StatsAggregateFixture(now, characters, keys);
    }

    /// <summary>
    /// Produces the repeat, modifier, shortcut, and Enter cases needed by the
    /// input-counting contract. The timestamps deliberately share one second.
    /// </summary>
    public static IReadOnlyList<StatsInputEventFixture> CreateInputSemanticsFixture(
        DateTimeOffset timestamp)
    {
        var app = CreateApplication(1);
        return
        [
            new(timestamp, PhysicalKeys.KeyA, app, IsRepeat: false, IsShortcutModified: false),
            new(timestamp.AddMilliseconds(80), PhysicalKeys.KeyA, app, IsRepeat: true, IsShortcutModified: false),
            new(timestamp.AddMilliseconds(160), PhysicalKeys.LeftShift, app, IsRepeat: false, IsShortcutModified: false),
            new(timestamp.AddMilliseconds(240), PhysicalKeys.KeyC, app, IsRepeat: false, IsShortcutModified: true),
            new(timestamp.AddMilliseconds(320), PhysicalKeys.Enter, app, IsRepeat: false, IsShortcutModified: false),
        ];
    }

    /// <summary>
    /// Creates dense but non-random history for screenshot and report tests.
    /// With the defaults, the final 365 days are the current period and the
    /// preceding 365 days are the comparison period.
    /// </summary>
    public static StatsUiHistoryFixture CreateUiHistoryFixture(
        DateOnly endDate,
        int dayCount = 730,
        int currentPeriodDayCount = 365,
        int applicationCount = 8)
    {
        if (dayCount is < 1 or > 3_660)
        {
            throw new ArgumentOutOfRangeException(nameof(dayCount));
        }

        if (currentPeriodDayCount is < 1 || currentPeriodDayCount > dayCount)
        {
            throw new ArgumentOutOfRangeException(nameof(currentPeriodDayCount));
        }

        if (applicationCount is < 1 or > 20)
        {
            throw new ArgumentOutOfRangeException(nameof(applicationCount));
        }

        var applications = Enumerable.Range(1, applicationCount)
            .Select(CreateApplication)
            .ToArray();
        var currentStartIndex = dayCount - currentPeriodDayCount;
        var currentCounts = new long[applicationCount];
        var previousCounts = new long[applicationCount];
        var startDate = endDate.AddDays(1 - dayCount);
        var days = new List<StatsDailyFixture>(dayCount);

        for (var dayIndex = 0; dayIndex < dayCount; dayIndex++)
        {
            var date = startDate.AddDays(dayIndex);
            var characterCount = dayIndex % 17 == 0
                ? 0
                : 800L + ((dayIndex * 7_919L + date.DayNumber * 37L) % 9_000L);
            var allocations = AllocateAcrossApplications(characterCount, applications, dayIndex);
            var isCurrentPeriod = dayIndex >= currentStartIndex;
            for (var applicationIndex = 0; applicationIndex < applications.Length; applicationIndex++)
            {
                var count = allocations[applications[applicationIndex].ProcessKey];
                if (isCurrentPeriod)
                {
                    currentCounts[applicationIndex] += count;
                }
                else
                {
                    previousCounts[applicationIndex] += count;
                }
            }

            var topApplication = characterCount == 0
                ? null
                : allocations.MaxBy(pair => pair.Value).Key;
            days.Add(new StatsDailyFixture(
                date,
                characterCount,
                PeakCps: characterCount == 0 ? 0 : 2 + (dayIndex % 12),
                ActiveSeconds: characterCount == 0 ? 0 : 60 + (characterCount / 11),
                topApplication,
                allocations));
        }

        var comparisons = applications
            .Select((application, index) => new StatsApplicationComparisonFixture(
                application,
                currentCounts[index],
                previousCounts[index]))
            .OrderByDescending(summary => summary.CurrentCharacterCount)
            .ThenBy(summary => summary.Application.ProcessKey, StringComparer.Ordinal)
            .ToArray();

        var generatedAt = new DateTimeOffset(
            endDate.ToDateTime(new TimeOnly(12, 0), DateTimeKind.Utc));
        return new StatsUiHistoryFixture(
            generatedAt,
            startDate,
            endDate,
            currentPeriodDayCount,
            applications,
            days,
            comparisons);
    }

    public static StatsApplicationFixture CreateApplication(int ordinal)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(ordinal);

        return new StatsApplicationFixture(
            $"com.example.battuta.fixture.{ordinal:D2}",
            $"示例应用 {ordinal:D2}",
            $"FixtureApp{ordinal:D2}",
            $"Battuta.FixtureApp.{ordinal:D2}");
    }

    private static ReadOnlyDictionary<string, long> AllocateAcrossApplications(
        long total,
        StatsApplicationFixture[] applications,
        int dayIndex)
    {
        if (total == 0)
        {
            return new ReadOnlyDictionary<string, long>(
                applications.ToDictionary(
                    application => application.ProcessKey,
                    _ => 0L,
                    StringComparer.Ordinal));
        }

        var weights = new int[applications.Length];
        var totalWeight = 0;
        for (var index = 0; index < applications.Length; index++)
        {
            weights[index] = ((index + dayIndex) % applications.Length) + 1;
            totalWeight += weights[index];
        }

        var remaining = total;
        var result = new Dictionary<string, long>(applications.Length, StringComparer.Ordinal);
        for (var index = 0; index < applications.Length; index++)
        {
            var count = index == applications.Length - 1
                ? remaining
                : total * weights[index] / totalWeight;
            remaining -= count;
            result.Add(applications[index].ProcessKey, count);
        }

        return new ReadOnlyDictionary<string, long>(result);
    }
}
