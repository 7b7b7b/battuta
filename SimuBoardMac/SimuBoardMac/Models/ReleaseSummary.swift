import Foundation

enum ReleaseSummaryValidationError: Error, Equatable, Sendable {
    case invalidTag
    case invalidReleaseURL
}

struct ReleaseSummary: Codable, Equatable, Identifiable, Sendable {
    static let releasePathPrefix = "/7b7b7b/simuboard/releases/"

    let tagName: String
    let version: SemanticVersion
    let releaseURL: URL
    let publishedAt: Date?

    var id: String { tagName }

    init(tagName: String, releaseURL: URL, publishedAt: Date?) throws {
        guard let version = SemanticVersion(tagName) else {
            throw ReleaseSummaryValidationError.invalidTag
        }
        guard Self.isAllowedReleaseURL(releaseURL) else {
            throw ReleaseSummaryValidationError.invalidReleaseURL
        }

        self.tagName = tagName
        self.version = version
        self.releaseURL = releaseURL
        self.publishedAt = publishedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tagName = try container.decode(String.self, forKey: .tagName)
        let releaseURL = try container.decode(URL.self, forKey: .releaseURL)
        let publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        try self.init(tagName: tagName, releaseURL: releaseURL, publishedAt: publishedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tagName, forKey: .tagName)
        try container.encode(releaseURL, forKey: .releaseURL)
        try container.encodeIfPresent(publishedAt, forKey: .publishedAt)
    }

    static func isAllowedReleaseURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "github.com"
            && url.path.hasPrefix(releasePathPrefix)
    }

    private enum CodingKeys: String, CodingKey {
        case tagName
        case releaseURL
        case publishedAt
    }
}
