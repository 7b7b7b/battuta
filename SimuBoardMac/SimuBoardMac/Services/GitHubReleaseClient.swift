import Foundation

struct GitHubRateLimit: Equatable, Sendable {
    let remaining: Int?
    let resetAt: Date?
}

enum GitHubReleaseFetchResult: Equatable, Sendable {
    case modified(release: ReleaseSummary, etag: String?, rateLimit: GitHubRateLimit)
    case notModified(etag: String?, rateLimit: GitHubRateLimit)
}

enum GitHubReleaseClientError: Error, Equatable, Sendable {
    case invalidResponse
    case malformedRelease
    case noPublishedRelease
    case apiVersionRetired
    case rateLimited(retryAt: Date)
    case httpStatus(Int)
}

struct GitHubReleaseClient: Sendable {
    var fetchLatest: @Sendable (_ etag: String?) async throws -> GitHubReleaseFetchResult

    static func live(
        session suppliedSession: URLSession? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> GitHubReleaseClient {
        let session = suppliedSession ?? makeSession()
        let endpoint = URL(string: "https://api.github.com/repos/wormforce/battuta/releases/latest")!

        return GitHubReleaseClient { etag in
            var request = URLRequest(url: endpoint)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("Battuta-macOS", forHTTPHeaderField: "User-Agent")
            if let etag, !etag.isEmpty {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }

            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw GitHubReleaseClientError.invalidResponse
            }

            let rateLimit = GitHubRateLimit(
                remaining: response.integerHeader(named: "X-RateLimit-Remaining"),
                resetAt: response.epochDateHeader(named: "X-RateLimit-Reset")
            )
            let responseETag = response.value(forHTTPHeaderField: "ETag") ?? etag

            switch response.statusCode {
            case 200:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                guard let payload = try? decoder.decode(GitHubReleasePayload.self, from: data),
                      !payload.draft,
                      !payload.prerelease,
                      let releaseURL = URL(string: payload.htmlURL),
                      let release = try? ReleaseSummary(
                          tagName: payload.tagName,
                          releaseURL: releaseURL,
                          publishedAt: payload.publishedAt
                      ) else {
                    throw GitHubReleaseClientError.malformedRelease
                }
                return .modified(release: release, etag: responseETag, rateLimit: rateLimit)

            case 304:
                return .notModified(etag: responseETag, rateLimit: rateLimit)

            case 404:
                throw GitHubReleaseClientError.noPublishedRelease

            case 410:
                throw GitHubReleaseClientError.apiVersionRetired

            case 403, 429:
                throw GitHubReleaseClientError.rateLimited(
                    retryAt: response.retryDate(relativeTo: now())
                )

            default:
                throw GitHubReleaseClientError.httpStatus(response.statusCode)
            }
        }
    }

    static func constant(_ result: GitHubReleaseFetchResult) -> GitHubReleaseClient {
        GitHubReleaseClient { _ in result }
    }

    static func failing(_ error: GitHubReleaseClientError) -> GitHubReleaseClient {
        GitHubReleaseClient { _ in throw error }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let publishedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case publishedAt = "published_at"
    }
}

private extension HTTPURLResponse {
    func integerHeader(named name: String) -> Int? {
        value(forHTTPHeaderField: name).flatMap(Int.init)
    }

    func epochDateHeader(named name: String) -> Date? {
        value(forHTTPHeaderField: name)
            .flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:))
    }

    func retryDate(relativeTo now: Date) -> Date {
        if let seconds = value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) {
            return now.addingTimeInterval(max(1, seconds))
        }
        if let reset = epochDateHeader(named: "X-RateLimit-Reset"), reset > now {
            return reset
        }
        return now.addingTimeInterval(60)
    }
}
