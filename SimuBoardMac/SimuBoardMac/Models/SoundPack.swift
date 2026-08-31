import CryptoKit
import Foundation

struct SoundPackAssetID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum SoundPackKeyOverride: Hashable, Sendable {
    case inherit
    case silent
    case asset(SoundPackAssetID)
}

extension SoundPackKeyOverride: Codable {
    private enum Kind: String, Codable {
        case inherit
        case silent
        case asset
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case assetID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .inherit:
            self = .inherit
        case .silent:
            self = .silent
        case .asset:
            guard let assetID = try container.decodeIfPresent(SoundPackAssetID.self, forKey: .assetID) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .assetID,
                    in: container,
                    debugDescription: "An asset override requires an assetID."
                )
            }
            self = .asset(assetID)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inherit:
            try container.encode(Kind.inherit, forKey: .kind)
        case .silent:
            try container.encode(Kind.silent, forKey: .kind)
        case let .asset(assetID):
            try container.encode(Kind.asset, forKey: .kind)
            try container.encode(assetID, forKey: .assetID)
        }
    }
}

struct SoundPackPhaseAssignments: Codable, Hashable, Sendable {
    var generic: SoundPackAssetID?
    var rows: [String: SoundPackAssetID]
    var specials: [String: SoundPackAssetID]
    var keyOverrides: [String: SoundPackKeyOverride]

    init(
        generic: SoundPackAssetID? = nil,
        rows: [String: SoundPackAssetID] = [:],
        specials: [String: SoundPackAssetID] = [:],
        keyOverrides: [String: SoundPackKeyOverride] = [:]
    ) {
        self.generic = generic
        self.rows = rows
        self.specials = specials
        self.keyOverrides = keyOverrides
    }

    func asset(for row: KeyboardRowID) -> SoundPackAssetID? {
        rows[row.rawValue]
    }

    mutating func setAsset(_ assetID: SoundPackAssetID?, for row: KeyboardRowID) {
        rows[row.rawValue] = assetID
    }

    func asset(for specialKey: KeyboardSpecialKeyID) -> SoundPackAssetID? {
        specials[specialKey.rawValue]
    }

    mutating func setAsset(_ assetID: SoundPackAssetID?, for specialKey: KeyboardSpecialKeyID) {
        specials[specialKey.rawValue] = assetID
    }

    func override(for keyID: KeyboardKeyID) -> SoundPackKeyOverride? {
        keyOverrides[keyID.rawValue]
    }

    mutating func setOverride(_ override: SoundPackKeyOverride?, for keyID: KeyboardKeyID) {
        keyOverrides[keyID.rawValue] = override
    }

    var referencedAssetIDs: Set<SoundPackAssetID> {
        var result = Set(rows.values)
        result.formUnion(specials.values)
        if let generic { result.insert(generic) }
        for override in keyOverrides.values {
            if case let .asset(assetID) = override { result.insert(assetID) }
        }
        return result
    }
}

struct SoundPackAssetLicense: Codable, Hashable, Sendable {
    var name: String
    var sourceURL: String?
    var author: String?
    var notice: String?
}

struct SoundPackAudioAsset: Codable, Identifiable, Hashable, Sendable {
    let id: SoundPackAssetID
    var relativePath: String
    var sha256: String
    var originalFilename: String?
    var durationSeconds: Double
    var sampleRate: Int
    var channelCount: Int
    var byteCount: Int64
    var license: SoundPackAssetLicense?

    init(
        id: SoundPackAssetID,
        relativePath: String,
        sha256: String,
        originalFilename: String? = nil,
        durationSeconds: Double,
        sampleRate: Int = 48_000,
        channelCount: Int = 1,
        byteCount: Int64,
        license: SoundPackAssetLicense? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.sha256 = sha256
        self.originalFilename = originalFilename
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.byteCount = byteCount
        self.license = license
    }
}

struct SoundPackAttribution: Codable, Hashable, Sendable {
    var title: String
    var author: String?
    var sourceURL: String?
    var licenseName: String?
    var notice: String?
}

struct SoundPackManifest: Codable, Identifiable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var name: String
    var author: String?
    var family: String?
    var tone: String?
    var notes: String?
    var baseProfileID: String?
    var layoutID: String
    var createdAt: Date
    var modifiedAt: Date
    var press: SoundPackPhaseAssignments
    var release: SoundPackPhaseAssignments
    var assets: [String: SoundPackAudioAsset]
    var attributions: [SoundPackAttribution]

    init(
        schemaVersion: Int = currentSchemaVersion,
        id: UUID = UUID(),
        name: String,
        author: String? = nil,
        family: String? = nil,
        tone: String? = nil,
        notes: String? = nil,
        baseProfileID: String? = nil,
        layoutID: String = KeyboardLayoutCatalog.defaultLayoutID,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        press: SoundPackPhaseAssignments = SoundPackPhaseAssignments(),
        release: SoundPackPhaseAssignments = SoundPackPhaseAssignments(),
        assets: [String: SoundPackAudioAsset] = [:],
        attributions: [SoundPackAttribution] = []
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.author = author
        self.family = family
        self.tone = tone
        self.notes = notes
        self.baseProfileID = baseProfileID
        self.layoutID = layoutID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.press = press
        self.release = release
        self.assets = assets
        self.attributions = attributions
    }

    func assignments(for phase: KeySoundPhase) -> SoundPackPhaseAssignments {
        phase == .press ? press : release
    }

    mutating func setAssignments(_ assignments: SoundPackPhaseAssignments, for phase: KeySoundPhase) {
        if phase == .press { press = assignments } else { release = assignments }
    }

    var referencedAssetIDs: Set<SoundPackAssetID> {
        press.referencedAssetIDs.union(release.referencedAssetIDs)
    }
}

enum SoundPackOrigin: Codable, Hashable, Sendable {
    case bundled(profileID: String)
    case bundledPack(packID: UUID)
    case custom(packID: UUID)

    var selectionID: String {
        switch self {
        case let .bundled(profileID): profileID
        case let .bundledPack(packID): "bundled-pack:\(packID.uuidString.lowercased())"
        case let .custom(packID): "custom:\(packID.uuidString.lowercased())"
        }
    }
}

struct SoundPackDescriptor: Identifiable, Codable, Hashable, Sendable {
    let origin: SoundPackOrigin
    var name: String
    var family: String
    var tone: String

    var id: String { origin.selectionID }

    var isReadOnly: Bool {
        if case .custom = origin { return false }
        return true
    }

    var bundledPackID: UUID? {
        guard case let .bundledPack(packID) = origin else { return nil }
        return packID
    }

    var customPackID: UUID? {
        guard case let .custom(packID) = origin else { return nil }
        return packID
    }

    static var bundledDefaults: [SoundPackDescriptor] {
        SwitchProfile.allCases.map { profile in
            SoundPackDescriptor(
                origin: .bundled(profileID: profile.rawValue),
                name: profile.displayName,
                family: profile.family,
                tone: profile.tone
            )
        }
    }

    static func bundledPack(manifest: SoundPackManifest) -> SoundPackDescriptor {
        SoundPackDescriptor(
            origin: .bundledPack(packID: manifest.id),
            name: manifest.name,
            family: manifest.family ?? "内置".localized,
            tone: manifest.tone ?? "内置音色".localized
        )
    }

    static func custom(manifest: SoundPackManifest) -> SoundPackDescriptor {
        SoundPackDescriptor(
            origin: .custom(packID: manifest.id),
            name: manifest.name,
            family: manifest.family ?? "DIY",
            tone: manifest.tone ?? "自定义音色".localized
        )
    }
}

struct SoundPackDocument: Identifiable, Sendable {
    let descriptor: SoundPackDescriptor
    let manifest: SoundPackManifest
    let rootURL: URL

    var id: String { descriptor.id }

    func assetURL(for assetID: SoundPackAssetID) throws -> URL {
        guard let asset = manifest.assets[assetID.rawValue] else {
            throw SoundPackError.missingAsset(assetID.rawValue)
        }
        return try SoundPackFileUtilities.descendantURL(
            for: asset.relativePath,
            under: rootURL
        )
    }
}

struct SoundPackValidationLimits: Hashable, Sendable {
    var maximumManifestBytes: Int64 = 1_048_576
    var maximumPackBytes: Int64 = 134_217_728
    var maximumAssetBytes: Int64 = 25_165_824
    var maximumAssetCount: Int = 256
    var maximumFileCount: Int = 512
    var maximumAudioDurationSeconds: Double = 5
    var maximumTotalAudioDurationSeconds: Double = 180
    var minimumAudioDurationSeconds: Double = 0.005
    var maximumTextLength: Int = 8_192

    static let standard = SoundPackValidationLimits()
}

enum SoundPackError: Error, LocalizedError, Sendable {
    case invalidManifest(String)
    case unsupportedSchema(Int)
    case unsafePath(String)
    case unsafeFile(String)
    case missingAsset(String)
    case invalidAudio(String)
    case sizeLimitExceeded(String)
    case hashMismatch(String)
    case packAlreadyExists(UUID)
    case packNotFound(UUID)
    case fileOperation(String)

    var errorDescription: String? {
        switch self {
        case let .invalidManifest(message):
            L10n.format("音色包清单无效：%@", message)
        case let .unsupportedSchema(version):
            L10n.format("不支持音色包格式版本 %@。", "\(version)")
        case let .unsafePath(path):
            L10n.format("音色包包含不安全路径：%@", path)
        case let .unsafeFile(path):
            L10n.format("音色包包含不安全文件：%@", path)
        case let .missingAsset(asset):
            L10n.format("音色包缺少音频资源：%@", asset)
        case let .invalidAudio(message):
            L10n.format("音频无效：%@", message)
        case let .sizeLimitExceeded(message):
            L10n.format("音色包超过安全限制：%@", message)
        case let .hashMismatch(path):
            L10n.format("音频校验失败：%@", path)
        case let .packAlreadyExists(id):
            L10n.format("音色包已存在：%@", id.uuidString)
        case let .packNotFound(id):
            L10n.format("找不到音色包：%@", id.uuidString)
        case let .fileOperation(message):
            L10n.format("文件操作失败：%@", message)
        }
    }
}

enum SoundPackCoding {
    static func encode(_ manifest: SoundPackManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    static func decode(
        _ data: Data,
        limits: SoundPackValidationLimits = .standard
    ) throws -> SoundPackManifest {
        guard data.count <= limits.maximumManifestBytes else {
            throw SoundPackError.sizeLimitExceeded(L10n.tr("manifest.json 过大"))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(SoundPackManifest.self, from: data)
        } catch {
            throw SoundPackError.invalidManifest(error.localizedDescription)
        }
    }
}

enum SoundPackValidator {
    static func validate(
        _ manifest: SoundPackManifest,
        limits: SoundPackValidationLimits = .standard
    ) throws {
        guard manifest.schemaVersion == SoundPackManifest.currentSchemaVersion else {
            throw SoundPackError.unsupportedSchema(manifest.schemaVersion)
        }
        try validateRequiredText(manifest.name, field: "name", maximum: 128)
        try validateRequiredText(manifest.layoutID, field: "layoutID", maximum: 128)
        guard manifest.layoutID == KeyboardLayoutCatalog.defaultLayoutID else {
            throw SoundPackError.invalidManifest(
                L10n.format("当前版本不支持键盘布局：%@", manifest.layoutID)
            )
        }
        try validateOptionalText(manifest.author, field: "author", limits: limits)
        try validateOptionalText(manifest.family, field: "family", limits: limits)
        try validateOptionalText(manifest.tone, field: "tone", limits: limits)
        try validateOptionalText(manifest.notes, field: "notes", limits: limits)
        try validateOptionalText(manifest.baseProfileID, field: "baseProfileID", limits: limits)
        if let baseProfileID = manifest.baseProfileID,
           SwitchProfile(rawValue: baseProfileID) == nil {
            throw SoundPackError.invalidManifest(
                L10n.format("baseProfileID 不是已知内置音色：%@", baseProfileID)
            )
        }

        guard manifest.assets.count <= limits.maximumAssetCount else {
            throw SoundPackError.sizeLimitExceeded(
                L10n.format("音频数量超过 %@", "\(limits.maximumAssetCount)")
            )
        }
        try validate(assignments: manifest.press, manifest: manifest, phase: "press")
        try validate(assignments: manifest.release, manifest: manifest, phase: "release")

        var paths = Set<String>()
        var totalAudioDuration: Double = 0
        for (dictionaryID, asset) in manifest.assets {
            guard dictionaryID == asset.id.rawValue else {
                throw SoundPackError.invalidManifest(L10n.tr("assets 字典键与资源 ID 不一致"))
            }
            guard asset.id.rawValue == asset.sha256,
                  isLowercaseSHA256(asset.sha256) else {
                throw SoundPackError.invalidManifest(L10n.tr("资源 ID 必须是小写 SHA-256"))
            }
            let expectedPath = "assets/\(asset.sha256).wav"
            guard asset.relativePath == expectedPath else {
                throw SoundPackError.unsafePath(asset.relativePath)
            }
            try SoundPackFileUtilities.validateRelativePath(asset.relativePath)
            guard paths.insert(asset.relativePath).inserted else {
                throw SoundPackError.invalidManifest(L10n.tr("多个资源使用相同路径"))
            }
            guard asset.durationSeconds.isFinite,
                  asset.durationSeconds >= limits.minimumAudioDurationSeconds,
                  asset.durationSeconds <= limits.maximumAudioDurationSeconds else {
                throw SoundPackError.invalidAudio(
                    L10n.format("%@ 时长超出范围", asset.relativePath)
                )
            }
            totalAudioDuration += asset.durationSeconds
            guard asset.sampleRate == 48_000, asset.channelCount == 1 else {
                throw SoundPackError.invalidAudio(
                    L10n.format("%@ 必须为 48 kHz 单声道", asset.relativePath)
                )
            }
            guard asset.byteCount > 0, asset.byteCount <= limits.maximumAssetBytes else {
                throw SoundPackError.sizeLimitExceeded(
                    L10n.format("%@ 文件过大", asset.relativePath)
                )
            }
            try validateOptionalText(asset.originalFilename, field: "originalFilename", limits: limits)
            if let license = asset.license {
                try validateRequiredText(license.name, field: "license.name", maximum: 256)
                try validateOptionalText(license.sourceURL, field: "license.sourceURL", limits: limits)
                try validateOptionalText(license.author, field: "license.author", limits: limits)
                try validateOptionalText(license.notice, field: "license.notice", limits: limits)
            }
        }
        guard totalAudioDuration.isFinite,
              totalAudioDuration <= limits.maximumTotalAudioDurationSeconds else {
            throw SoundPackError.sizeLimitExceeded(
                L10n.format(
                    "音频总时长超过 %@ 秒",
                    "\(Int(limits.maximumTotalAudioDurationSeconds))"
                )
            )
        }

        guard manifest.attributions.count <= limits.maximumAssetCount else {
            throw SoundPackError.sizeLimitExceeded(L10n.tr("署名条目过多"))
        }
        for attribution in manifest.attributions {
            try validateRequiredText(attribution.title, field: "attribution.title", maximum: 512)
            try validateOptionalText(attribution.author, field: "attribution.author", limits: limits)
            try validateOptionalText(attribution.sourceURL, field: "attribution.sourceURL", limits: limits)
            try validateOptionalText(attribution.licenseName, field: "attribution.licenseName", limits: limits)
            try validateOptionalText(attribution.notice, field: "attribution.notice", limits: limits)
        }
    }

    private static func validate(
        assignments: SoundPackPhaseAssignments,
        manifest: SoundPackManifest,
        phase: String
    ) throws {
        let allowedRows = Set(KeyboardRowID.allCases.map(\.rawValue))
        let unknownRows = Set(assignments.rows.keys).subtracting(allowedRows)
        guard unknownRows.isEmpty else {
            throw SoundPackError.invalidManifest(
                L10n.format(
                    "%@ 包含未知行：%@",
                    phase,
                    String(describing: unknownRows.sorted())
                )
            )
        }

        let allowedSpecials = Set(KeyboardSpecialKeyID.allCases.map(\.rawValue))
        let unknownSpecials = Set(assignments.specials.keys).subtracting(allowedSpecials)
        guard unknownSpecials.isEmpty else {
            throw SoundPackError.invalidManifest(
                L10n.format(
                    "%@ 包含未知特殊键：%@",
                    phase,
                    String(describing: unknownSpecials.sorted())
                )
            )
        }

        for key in assignments.keyOverrides.keys {
            guard isSafeIdentifier(key) else {
                throw SoundPackError.invalidManifest(
                    L10n.format("%@ 包含无效按键 ID：%@", phase, key)
                )
            }
        }

        for assetID in assignments.referencedAssetIDs {
            guard manifest.assets[assetID.rawValue] != nil else {
                throw SoundPackError.missingAsset(assetID.rawValue)
            }
        }
    }

    private static func validateRequiredText(
        _ value: String,
        field: String,
        maximum: Int
    ) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, value.count <= maximum else {
            throw SoundPackError.invalidManifest(
                L10n.format("%@ 为空或过长", field)
            )
        }
    }

    private static func validateOptionalText(
        _ value: String?,
        field: String,
        limits: SoundPackValidationLimits
    ) throws {
        guard let value else { return }
        guard value.count <= limits.maximumTextLength else {
            throw SoundPackError.invalidManifest(L10n.format("%@ 过长", field))
        }
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "_" || $0 == "-"
        }
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        guard value.count == 64 else { return false }
        return value.unicodeScalars.allSatisfy {
            ("0"..."9").contains(Character($0)) || ("a"..."f").contains(Character($0))
        }
    }
}

enum SoundPackFileUtilities {
    static func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty,
              path.utf8.count <= 1_024,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("\0") else {
            throw SoundPackError.unsafePath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.count <= 16,
              components.allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255
              }) else {
            throw SoundPackError.unsafePath(path)
        }
    }

    static func descendantURL(for relativePath: String, under rootURL: URL) throws -> URL {
        try validateRelativePath(relativePath)
        let root = rootURL.standardizedFileURL
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else {
            throw SoundPackError.unsafePath(relativePath)
        }
        return candidate
    }

    static func validateRegularFile(at url: URL) throws -> Int64 {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
                .fileSizeKey,
            ])
        } catch {
            throw SoundPackError.fileOperation(error.localizedDescription)
        }
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              values.isAliasFile != true else {
            throw SoundPackError.unsafeFile(url.path)
        }
        return Int64(values.fileSize ?? 0)
    }

    static func sha256(of url: URL) throws -> String {
        _ = try validateRegularFile(at: url)
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw SoundPackError.fileOperation(error.localizedDescription)
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        do {
            while let data = try handle.read(upToCount: 64 * 1_024), !data.isEmpty {
                hasher.update(data: data)
            }
        } catch {
            throw SoundPackError.fileOperation(error.localizedDescription)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
