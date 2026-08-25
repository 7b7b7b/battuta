namespace Battuta.Windows.Updates;

public sealed record GitHubReleaseSummary(
    string TagName,
    SemanticVersion Version,
    Uri ReleaseUri,
    DateTimeOffset? PublishedAt)
{
    public const string AllowedReleasePathPrefix = "/7b7b7b/battuta/releases/";

    public static GitHubReleaseSummary Create(
        string tagName,
        Uri releaseUri,
        DateTimeOffset? publishedAt)
    {
        if (!SemanticVersion.TryParse(tagName, out var version))
        {
            throw new ArgumentException("The GitHub release tag is not a semantic version.", nameof(tagName));
        }

        if (!IsAllowedReleaseUri(releaseUri))
        {
            throw new ArgumentException("The release URL is outside the Battuta GitHub repository.", nameof(releaseUri));
        }

        return new GitHubReleaseSummary(tagName, version, releaseUri, publishedAt);
    }

    public static bool IsAllowedReleaseUri(Uri? uri) =>
        uri is { IsAbsoluteUri: true }
        && uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)
        && uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase)
        && uri.AbsolutePath.StartsWith(AllowedReleasePathPrefix, StringComparison.Ordinal);
}

public sealed record GitHubRateLimit(int? Remaining, DateTimeOffset? ResetAt);

public abstract record ReleaseFetchResult(GitHubRateLimit RateLimit, string? ETag)
{
    public sealed record Modified(
        GitHubReleaseSummary Release,
        GitHubRateLimit Limit,
        string? ResponseETag) : ReleaseFetchResult(Limit, ResponseETag);

    public sealed record NotModified(
        GitHubRateLimit Limit,
        string? ResponseETag) : ReleaseFetchResult(Limit, ResponseETag);
}

public enum ReleaseClientErrorKind
{
    InvalidResponse,
    MalformedRelease,
    NoPublishedRelease,
    ApiVersionRetired,
    RateLimited,
    HttpStatus,
}

public sealed class ReleaseClientException : Exception
{
    public ReleaseClientException(
        ReleaseClientErrorKind kind,
        string message,
        int? statusCode = null,
        DateTimeOffset? retryAt = null,
        Exception? innerException = null)
        : base(message, innerException)
    {
        Kind = kind;
        StatusCode = statusCode;
        RetryAt = retryAt;
    }

    public ReleaseClientErrorKind Kind { get; }

    public int? StatusCode { get; }

    public DateTimeOffset? RetryAt { get; }
}
