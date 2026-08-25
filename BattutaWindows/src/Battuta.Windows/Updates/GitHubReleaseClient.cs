using System.Globalization;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;

namespace Battuta.Windows.Updates;

public sealed class GitHubReleaseClient : IReleaseClient
{
    public static readonly Uri LatestReleaseEndpoint = new(
        "https://api.github.com/repos/7b7b7b/battuta/releases/latest");

    private readonly HttpClient _httpClient;
    private readonly TimeProvider _timeProvider;

    public GitHubReleaseClient(HttpClient httpClient, TimeProvider? timeProvider = null)
    {
        _httpClient = httpClient ?? throw new ArgumentNullException(nameof(httpClient));
        _timeProvider = timeProvider ?? TimeProvider.System;
    }

    public async Task<ReleaseFetchResult> FetchLatestAsync(
        string? etag,
        CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, LatestReleaseEndpoint);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        request.Headers.TryAddWithoutValidation("X-GitHub-Api-Version", "2026-03-10");
        request.Headers.UserAgent.ParseAdd("Battuta-Windows/1.0");
        if (!string.IsNullOrWhiteSpace(etag))
        {
            request.Headers.TryAddWithoutValidation("If-None-Match", etag);
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(10));
        using var response = await _httpClient.SendAsync(
            request,
            HttpCompletionOption.ResponseHeadersRead,
            timeout.Token).ConfigureAwait(false);

        var rateLimit = ReadRateLimit(response);
        var responseEtag = response.Headers.ETag?.ToString() ?? etag;
        if (response.StatusCode == HttpStatusCode.NotModified)
        {
            return new ReleaseFetchResult.NotModified(rateLimit, responseEtag);
        }

        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            throw new ReleaseClientException(
                ReleaseClientErrorKind.NoPublishedRelease,
                "GitHub has no published Battuta release.",
                statusCode: (int)response.StatusCode);
        }

        if (response.StatusCode == HttpStatusCode.Gone)
        {
            throw new ReleaseClientException(
                ReleaseClientErrorKind.ApiVersionRetired,
                "The configured GitHub API version is no longer available.",
                statusCode: (int)response.StatusCode);
        }

        if (response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.TooManyRequests)
        {
            throw new ReleaseClientException(
                ReleaseClientErrorKind.RateLimited,
                "GitHub temporarily rate-limited update checks.",
                statusCode: (int)response.StatusCode,
                retryAt: ResolveRetryAt(response));
        }

        if (!response.IsSuccessStatusCode)
        {
            throw new ReleaseClientException(
                ReleaseClientErrorKind.HttpStatus,
                $"GitHub returned HTTP {(int)response.StatusCode}.",
                statusCode: (int)response.StatusCode);
        }

        try
        {
            await using var stream = await response.Content.ReadAsStreamAsync(timeout.Token)
                .ConfigureAwait(false);
            var payload = await JsonSerializer.DeserializeAsync<GitHubReleasePayload>(
                stream,
                cancellationToken: timeout.Token).ConfigureAwait(false);
            if (payload is null
                || payload.Draft
                || payload.Prerelease
                || string.IsNullOrWhiteSpace(payload.TagName)
                || !Uri.TryCreate(payload.HtmlUrl, UriKind.Absolute, out var releaseUri))
            {
                throw new ReleaseClientException(
                    ReleaseClientErrorKind.MalformedRelease,
                    "GitHub returned a malformed Battuta release.");
            }

            GitHubReleaseSummary release;
            try
            {
                release = GitHubReleaseSummary.Create(payload.TagName, releaseUri, payload.PublishedAt);
            }
            catch (ArgumentException exception)
            {
                throw new ReleaseClientException(
                    ReleaseClientErrorKind.MalformedRelease,
                    "GitHub returned an invalid Battuta release.",
                    innerException: exception);
            }

            return new ReleaseFetchResult.Modified(release, rateLimit, responseEtag);
        }
        catch (JsonException exception)
        {
            throw new ReleaseClientException(
                ReleaseClientErrorKind.InvalidResponse,
                "GitHub returned invalid JSON.",
                innerException: exception);
        }
    }

    private static GitHubRateLimit ReadRateLimit(HttpResponseMessage response)
    {
        int? remaining = null;
        DateTimeOffset? resetAt = null;
        if (response.Headers.TryGetValues("X-RateLimit-Remaining", out var remainingValues)
            && int.TryParse(remainingValues.FirstOrDefault(), out var parsedRemaining))
        {
            remaining = parsedRemaining;
        }

        if (response.Headers.TryGetValues("X-RateLimit-Reset", out var resetValues)
            && long.TryParse(resetValues.FirstOrDefault(), out var epochSeconds))
        {
            resetAt = DateTimeOffset.FromUnixTimeSeconds(epochSeconds);
        }

        return new GitHubRateLimit(remaining, resetAt);
    }

    private DateTimeOffset ResolveRetryAt(HttpResponseMessage response)
    {
        var now = _timeProvider.GetUtcNow();
        if (response.Headers.RetryAfter?.Delta is { } delta)
        {
            return now.Add(delta < TimeSpan.FromSeconds(1) ? TimeSpan.FromSeconds(1) : delta);
        }

        if (response.Headers.RetryAfter?.Date is { } date && date > now)
        {
            return date;
        }

        if (response.Headers.TryGetValues("X-RateLimit-Reset", out var resetValues)
            && long.TryParse(
                resetValues.FirstOrDefault(),
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out var epochSeconds))
        {
            var reset = DateTimeOffset.FromUnixTimeSeconds(epochSeconds);
            if (reset > now)
            {
                return reset;
            }
        }

        return now.AddMinutes(1);
    }

    private sealed class GitHubReleasePayload
    {
        [System.Text.Json.Serialization.JsonPropertyName("tag_name")]
        public string? TagName { get; init; }

        [System.Text.Json.Serialization.JsonPropertyName("html_url")]
        public string? HtmlUrl { get; init; }

        [System.Text.Json.Serialization.JsonPropertyName("draft")]
        public bool Draft { get; init; }

        [System.Text.Json.Serialization.JsonPropertyName("prerelease")]
        public bool Prerelease { get; init; }

        [System.Text.Json.Serialization.JsonPropertyName("published_at")]
        public DateTimeOffset? PublishedAt { get; init; }
    }
}
