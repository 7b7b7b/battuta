namespace Battuta.Windows.Updates;

public interface IReleaseClient
{
    Task<ReleaseFetchResult> FetchLatestAsync(
        string? etag,
        CancellationToken cancellationToken = default);
}
