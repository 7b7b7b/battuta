using System.Net.Http;

namespace Battuta.Windows.Updates;

public enum UpdateCheckTrigger
{
    Automatic,
    Manual,
}

public enum UpdateComparison
{
    UpdateAvailable,
    UpToDate,
    InstalledVersionIsNewer,
}

public enum UpdateCheckFailureKind
{
    Offline,
    TimedOut,
    RequestedTooSoon,
    RateLimited,
    NoPublishedRelease,
    ApiVersionRetired,
    InvalidResponse,
    ServerUnavailable,
}

public sealed record UpdateCheckReport(
    UpdateComparison Comparison,
    GitHubReleaseSummary Release,
    SemanticVersion InstalledVersion,
    DateTimeOffset CheckedAt);

public sealed record UpdateCheckFailure(
    UpdateCheckFailureKind Kind,
    string Message,
    DateTimeOffset? RetryAt = null,
    UpdateCheckReport? CachedReport = null);

public sealed record UpdateCheckOutcome(
    UpdateCheckReport? Report,
    UpdateCheckFailure? Failure,
    bool WasSkipped = false);

/// <summary>
/// Shared update-check policy matching the macOS client: ETag caching, sparse
/// automatic checks, manual throttling, and GitHub rate-limit backoff.
/// </summary>
public sealed class UpdateCheckService : IDisposable
{
    public static readonly TimeSpan AutomaticRequestSpacing = TimeSpan.FromMinutes(5);
    public static readonly TimeSpan ManualRequestSpacing = TimeSpan.FromSeconds(65);

    private readonly IReleaseClient _client;
    private readonly IUpdateCacheStore _cacheStore;
    private readonly SemanticVersion _installedVersion;
    private readonly TimeProvider _timeProvider;
    private readonly SemaphoreSlim _checkGate = new(1, 1);
    private bool _disposed;

    public UpdateCheckService(
        IReleaseClient client,
        IUpdateCacheStore cacheStore,
        SemanticVersion installedVersion,
        TimeProvider? timeProvider = null)
    {
        _client = client ?? throw new ArgumentNullException(nameof(client));
        _cacheStore = cacheStore ?? throw new ArgumentNullException(nameof(cacheStore));
        _installedVersion = installedVersion;
        _timeProvider = timeProvider ?? TimeProvider.System;
    }

    public async Task<UpdateCheckOutcome> CheckAsync(
        UpdateCheckTrigger trigger,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        await _checkGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var cache = await _cacheStore.LoadAsync(cancellationToken).ConfigureAwait(false);
            var now = _timeProvider.GetUtcNow();
            var cachedReport = MakeCachedReport(cache);

            if (cache.RateLimitedUntil is { } rateLimitedUntil && rateLimitedUntil > now)
            {
                return Failure(
                    UpdateCheckFailureKind.RateLimited,
                    "GitHub 暂时限制请求。",
                    rateLimitedUntil,
                    cachedReport);
            }

            var spacing = trigger == UpdateCheckTrigger.Automatic
                ? AutomaticRequestSpacing
                : ManualRequestSpacing;
            if (cache.LastAttemptAt is { } lastAttempt && now - lastAttempt < spacing)
            {
                var retryAt = lastAttempt.Add(spacing);
                if (trigger == UpdateCheckTrigger.Automatic)
                {
                    return new UpdateCheckOutcome(cachedReport, null, WasSkipped: true);
                }

                return Failure(
                    UpdateCheckFailureKind.RequestedTooSoon,
                    "刚刚检查过更新。",
                    retryAt,
                    cachedReport);
            }

            cache = cache with { LastAttemptAt = now };
            await _cacheStore.SaveAsync(cache, cancellationToken).ConfigureAwait(false);

            try
            {
                var response = await _client.FetchLatestAsync(cache.ETag, cancellationToken)
                    .ConfigureAwait(false);
                GitHubReleaseSummary release;
                if (response is ReleaseFetchResult.Modified modified)
                {
                    release = modified.Release;
                    cache = cache with
                    {
                        ETag = modified.ETag,
                        LatestTagName = release.TagName,
                        LatestReleaseUri = release.ReleaseUri,
                        LatestPublishedAt = release.PublishedAt,
                    };
                }
                else
                {
                    release = cache.TryGetRelease()
                        ?? throw new ReleaseClientException(
                            ReleaseClientErrorKind.InvalidResponse,
                            "GitHub returned 304 without a cached release.");
                    cache = cache with { ETag = response.ETag };
                }

                var checkedAt = _timeProvider.GetUtcNow();
                cache = cache with
                {
                    LastSuccessfulCheckAt = checkedAt,
                    LastFailedCheckAt = null,
                    RateLimitedUntil = response.RateLimit.Remaining == 0
                        && response.RateLimit.ResetAt > checkedAt
                            ? response.RateLimit.ResetAt
                            : null,
                };
                await _cacheStore.SaveAsync(cache, cancellationToken).ConfigureAwait(false);
                return new UpdateCheckOutcome(MakeReport(release, checkedAt), null);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                return await RecordFailureAsync(
                    cache,
                    UpdateCheckFailureKind.TimedOut,
                    "连接 GitHub 超时。",
                    cachedReport,
                    cancellationToken).ConfigureAwait(false);
            }
            catch (HttpRequestException exception)
            {
                var kind = exception.HttpRequestError is HttpRequestError.NameResolutionError
                    or HttpRequestError.ConnectionError
                    ? UpdateCheckFailureKind.Offline
                    : UpdateCheckFailureKind.ServerUnavailable;
                return await RecordFailureAsync(
                    cache,
                    kind,
                    kind == UpdateCheckFailureKind.Offline ? "当前离线。" : "暂时无法连接 GitHub。",
                    cachedReport,
                    cancellationToken).ConfigureAwait(false);
            }
            catch (ReleaseClientException exception)
            {
                var kind = exception.Kind switch
                {
                    ReleaseClientErrorKind.RateLimited => UpdateCheckFailureKind.RateLimited,
                    ReleaseClientErrorKind.NoPublishedRelease => UpdateCheckFailureKind.NoPublishedRelease,
                    ReleaseClientErrorKind.ApiVersionRetired => UpdateCheckFailureKind.ApiVersionRetired,
                    ReleaseClientErrorKind.HttpStatus when exception.StatusCode >= 500 =>
                        UpdateCheckFailureKind.ServerUnavailable,
                    _ => UpdateCheckFailureKind.InvalidResponse,
                };
                if (kind == UpdateCheckFailureKind.RateLimited)
                {
                    cache = cache with { RateLimitedUntil = exception.RetryAt };
                }

                return await RecordFailureAsync(
                    cache,
                    kind,
                    exception.Message,
                    cachedReport,
                    cancellationToken,
                    exception.RetryAt).ConfigureAwait(false);
            }
        }
        finally
        {
            _checkGate.Release();
        }
    }

    private UpdateCheckReport? MakeCachedReport(UpdateCacheSnapshot cache)
    {
        var release = cache.TryGetRelease();
        return release is not null && cache.LastSuccessfulCheckAt is { } checkedAt
            ? MakeReport(release, checkedAt)
            : null;
    }

    private UpdateCheckReport MakeReport(GitHubReleaseSummary release, DateTimeOffset checkedAt)
    {
        var comparison = release.Version > _installedVersion
            ? UpdateComparison.UpdateAvailable
            : release.Version == _installedVersion
                ? UpdateComparison.UpToDate
                : UpdateComparison.InstalledVersionIsNewer;
        return new UpdateCheckReport(comparison, release, _installedVersion, checkedAt);
    }

    private async Task<UpdateCheckOutcome> RecordFailureAsync(
        UpdateCacheSnapshot cache,
        UpdateCheckFailureKind kind,
        string message,
        UpdateCheckReport? cachedReport,
        CancellationToken cancellationToken,
        DateTimeOffset? retryAt = null)
    {
        cache = cache with { LastFailedCheckAt = _timeProvider.GetUtcNow() };
        await _cacheStore.SaveAsync(cache, cancellationToken).ConfigureAwait(false);
        return Failure(kind, message, retryAt, cachedReport);
    }

    private static UpdateCheckOutcome Failure(
        UpdateCheckFailureKind kind,
        string message,
        DateTimeOffset? retryAt,
        UpdateCheckReport? cachedReport) =>
        new(cachedReport, new UpdateCheckFailure(kind, message, retryAt, cachedReport));

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _checkGate.Dispose();
    }
}
