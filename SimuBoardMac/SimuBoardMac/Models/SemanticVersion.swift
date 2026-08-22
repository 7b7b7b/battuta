import Foundation

struct SemanticVersion: Codable, Comparable, CustomStringConvertible, Hashable, Sendable {
    enum PrereleaseIdentifier: Codable, Hashable, Sendable {
        case numeric(Int)
        case alphaNumeric(String)

        fileprivate var description: String {
            switch self {
            case let .numeric(value): String(value)
            case let .alphaNumeric(value): value
            }
        }
    }

    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [PrereleaseIdentifier]
    let buildMetadata: [String]

    init(
        major: Int,
        minor: Int,
        patch: Int,
        prerelease: [PrereleaseIdentifier] = [],
        buildMetadata: [String] = []
    ) {
        precondition(major >= 0 && minor >= 0 && patch >= 0)
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.buildMetadata = buildMetadata
    }

    init?(_ tagOrVersion: String) {
        var value = tagOrVersion
        if value.first == "v" {
            value.removeFirst()
        }

        let buildParts = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard buildParts.count <= 2 else { return nil }

        let versionAndPrerelease = String(buildParts[0])
        let metadata: [String]
        if buildParts.count == 2 {
            metadata = buildParts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard !metadata.isEmpty, metadata.allSatisfy(Self.isValidIdentifier) else { return nil }
        } else {
            metadata = []
        }

        let prereleaseParts = versionAndPrerelease.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let coreParts = prereleaseParts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard coreParts.count == 3,
              let major = Self.parseCoreNumber(coreParts[0]),
              let minor = Self.parseCoreNumber(coreParts[1]),
              let patch = Self.parseCoreNumber(coreParts[2]) else { return nil }

        let prerelease: [PrereleaseIdentifier]
        if prereleaseParts.count == 2 {
            let identifiers = prereleaseParts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty else { return nil }

            var parsed: [PrereleaseIdentifier] = []
            parsed.reserveCapacity(identifiers.count)
            for identifier in identifiers {
                let text = String(identifier)
                guard Self.isValidIdentifier(text) else { return nil }
                if Self.isASCIIInteger(text) {
                    guard text == "0" || text.first != "0", let number = Int(text) else { return nil }
                    parsed.append(.numeric(number))
                } else {
                    parsed.append(.alphaNumeric(text))
                }
            }
            prerelease = parsed
        } else {
            prerelease = []
        }

        self.init(
            major: major,
            minor: minor,
            patch: patch,
            prerelease: prerelease,
            buildMetadata: metadata
        )
    }

    var description: String {
        var value = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty {
            value += "-" + prerelease.map(\.description).joined(separator: ".")
        }
        if !buildMetadata.isEmpty {
            value += "+" + buildMetadata.joined(separator: ".")
        }
        return value
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.major == rhs.major
            && lhs.minor == rhs.minor
            && lhs.patch == rhs.patch
            && lhs.prerelease == rhs.prerelease
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prerelease)
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (true, false): return false
        case (false, true): return true
        case (false, false): break
        }

        for (left, right) in zip(lhs.prerelease, rhs.prerelease) {
            if left == right { continue }
            switch (left, right) {
            case let (.numeric(leftValue), .numeric(rightValue)):
                return leftValue < rightValue
            case (.numeric, .alphaNumeric):
                return true
            case (.alphaNumeric, .numeric):
                return false
            case let (.alphaNumeric(leftValue), .alphaNumeric(rightValue)):
                return leftValue < rightValue
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func parseCoreNumber(_ value: Substring) -> Int? {
        let text = String(value)
        guard isASCIIInteger(text), text == "0" || text.first != "0" else { return nil }
        return Int(text)
    }

    private static func isASCIIInteger(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122)
                || byte == 45
        }
    }
}
