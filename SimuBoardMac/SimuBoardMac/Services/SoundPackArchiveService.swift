import Foundation

enum SoundPackImportCollisionPolicy: Sendable {
    case duplicate
    case replace
    case reject
}

enum SoundPackPackageValidator {
    static func validatePackage(
        at packageURL: URL,
        limits: SoundPackValidationLimits = .standard,
        fileManager: FileManager = .default
    ) throws -> SoundPackManifest {
        let root = packageURL.standardizedFileURL
        let rootValues: URLResourceValues
        do {
            rootValues = try root.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ])
        } catch {
            throw SoundPackError.fileOperation(error.localizedDescription)
        }
        guard rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true,
              rootValues.isAliasFile != true else {
            throw SoundPackError.unsafeFile(root.path)
        }
        guard root.pathExtension.lowercased() == "simuboardpack" else {
            throw SoundPackError.invalidManifest(L10n.tr("包扩展名必须是 .simuboardpack"))
        }

        let manifestURL = root.appendingPathComponent("manifest.json")
        let manifestByteCount = try SoundPackFileUtilities.validateRegularFile(at: manifestURL)
        guard manifestByteCount <= limits.maximumManifestBytes else {
            throw SoundPackError.sizeLimitExceeded(L10n.tr("manifest.json 过大"))
        }
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        } catch {
            throw SoundPackError.fileOperation(error.localizedDescription)
        }
        let manifest = try SoundPackCoding.decode(manifestData, limits: limits)
        try SoundPackValidator.validate(manifest, limits: limits)

        let expectedAssetPaths = Set(manifest.assets.values.map(\.relativePath))
        var discoveredAssetPaths = Set<String>()
        var totalByteCount: Int64 = 0
        var entryCount = 0
        var enumerationFailure: String?
        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
            .fileSizeKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: [],
            errorHandler: { url, error in
                enumerationFailure = "\(url.path): \(error.localizedDescription)"
                return false
            }
        ) else {
            throw SoundPackError.fileOperation(L10n.tr("无法读取音色包目录"))
        }

        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        for case let itemURL as URL in enumerator {
            let item = itemURL.standardizedFileURL
            guard item.path.hasPrefix(rootPrefix) else {
                throw SoundPackError.unsafePath(item.path)
            }
            let relativePath = String(item.path.dropFirst(rootPrefix.count))
            try SoundPackFileUtilities.validateRelativePath(relativePath)
            entryCount += 1
            guard entryCount <= limits.maximumFileCount else {
                throw SoundPackError.sizeLimitExceeded(
                    L10n.format("目录项数量超过 %@", "\(limits.maximumFileCount)")
                )
            }
            let values = try item.resourceValues(forKeys: Set(resourceKeys))
            guard values.isSymbolicLink != true, values.isAliasFile != true else {
                throw SoundPackError.unsafeFile(relativePath)
            }

            if values.isDirectory == true {
                let isAllowedDirectory = relativePath == "assets"
                    || relativePath == "licenses"
                    || relativePath.hasPrefix("licenses/")
                guard isAllowedDirectory else {
                    throw SoundPackError.unsafePath(relativePath)
                }
                continue
            }
            guard values.isRegularFile == true else {
                throw SoundPackError.unsafeFile(relativePath)
            }

            let byteCount = Int64(values.fileSize ?? 0)
            guard byteCount >= 0, byteCount <= limits.maximumAssetBytes else {
                throw SoundPackError.sizeLimitExceeded(relativePath)
            }
            let (nextTotal, overflow) = totalByteCount.addingReportingOverflow(byteCount)
            guard !overflow, nextTotal <= limits.maximumPackBytes else {
                throw SoundPackError.sizeLimitExceeded(L10n.tr("音色包总大小过大"))
            }
            totalByteCount = nextTotal

            if relativePath == "manifest.json" {
                continue
            } else if expectedAssetPaths.contains(relativePath) {
                discoveredAssetPaths.insert(relativePath)
            } else if relativePath.hasPrefix("licenses/") {
                continue
            } else if item.lastPathComponent == ".DS_Store" {
                continue
            } else {
                throw SoundPackError.unsafePath(relativePath)
            }
        }
        if let enumerationFailure {
            throw SoundPackError.fileOperation(enumerationFailure)
        }
        guard discoveredAssetPaths == expectedAssetPaths else {
            let missing = expectedAssetPaths.subtracting(discoveredAssetPaths).sorted()
            throw SoundPackError.missingAsset(missing.joined(separator: ", "))
        }

        for asset in manifest.assets.values {
            let url = try SoundPackFileUtilities.descendantURL(
                for: asset.relativePath,
                under: root
            )
            let info = try AudioImportService.validateNormalizedAudio(at: url, limits: limits)
            guard info.byteCount == asset.byteCount,
                  abs(info.durationSeconds - asset.durationSeconds) < 0.002 else {
                throw SoundPackError.invalidAudio(
                    L10n.format("%@ 元数据不匹配", asset.relativePath)
                )
            }
            let hash = try SoundPackFileUtilities.sha256(of: url)
            guard hash == asset.sha256 else {
                throw SoundPackError.hashMismatch(asset.relativePath)
            }
        }
        return manifest
    }

    static func licenseFiles(
        at packageURL: URL,
        fileManager: FileManager = .default
    ) throws -> [String: URL] {
        let licensesRoot = packageURL.appendingPathComponent("licenses", isDirectory: true)
        guard fileManager.fileExists(atPath: licensesRoot.path) else { return [:] }
        let rootValues = try licensesRoot.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
        ])
        guard rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true,
              rootValues.isAliasFile != true else {
            throw SoundPackError.unsafeFile(licensesRoot.path)
        }

        var result: [String: URL] = [:]
        guard let enumerator = fileManager.enumerator(
            at: licensesRoot,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ]
        ) else {
            throw SoundPackError.fileOperation(L10n.tr("无法读取 licenses"))
        }
        let prefix = licensesRoot.standardizedFileURL.path + "/"
        for case let itemURL as URL in enumerator {
            let values = try itemURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ])
            guard values.isSymbolicLink != true, values.isAliasFile != true else {
                throw SoundPackError.unsafeFile(itemURL.path)
            }
            guard values.isRegularFile == true else { continue }
            let path = itemURL.standardizedFileURL.path
            guard path.hasPrefix(prefix) else {
                throw SoundPackError.unsafePath(path)
            }
            let relativeName = String(path.dropFirst(prefix.count))
            try SoundPackFileUtilities.validateRelativePath("licenses/\(relativeName)")
            result[relativeName] = itemURL
        }
        return result
    }
}

actor SoundPackArchiveService {
    private let fileManager: FileManager
    private let limits: SoundPackValidationLimits

    init(
        limits: SoundPackValidationLimits = .standard,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.limits = limits
    }

    func validate(at packageURL: URL) throws -> SoundPackManifest {
        try SoundPackPackageValidator.validatePackage(
            at: packageURL,
            limits: limits,
            fileManager: fileManager
        )
    }

    @discardableResult
    func importPack(
        at sourceURL: URL,
        into library: SoundPackLibrary,
        collisionPolicy: SoundPackImportCollisionPolicy = .duplicate
    ) async throws -> SoundPackDescriptor {
        let manifest = try SoundPackPackageValidator.validatePackage(
            at: sourceURL,
            limits: limits,
            fileManager: fileManager
        )

        let assetFiles = try Dictionary(
            uniqueKeysWithValues: manifest.assets.values.map { asset in
                (
                    asset.id,
                    try SoundPackFileUtilities.descendantURL(
                        for: asset.relativePath,
                        under: sourceURL
                    )
                )
            }
        )
        let licenses = try SoundPackPackageValidator.licenseFiles(
            at: sourceURL,
            fileManager: fileManager
        )
        return try await library.saveImported(
            manifest: manifest,
            assetFiles: assetFiles,
            licenseFiles: licenses,
            collisionPolicy: collisionPolicy
        )
    }

    @discardableResult
    func export(
        customPackID: UUID,
        from library: SoundPackLibrary,
        to destinationURL: URL
    ) async throws -> URL {
        let document = try await library.loadCustomPack(id: customPackID)
        return try export(document: document, to: destinationURL)
    }

    @discardableResult
    func export(
        document: SoundPackDocument,
        to requestedDestinationURL: URL
    ) throws -> URL {
        _ = try SoundPackPackageValidator.validatePackage(
            at: document.rootURL,
            limits: limits,
            fileManager: fileManager
        )
        let destination = requestedDestinationURL.pathExtension.lowercased() == "simuboardpack"
            ? requestedDestinationURL
            : requestedDestinationURL.appendingPathExtension("simuboardpack")
        let standardizedDestination = destination.standardizedFileURL
        let sourcePrefix = document.rootURL.standardizedFileURL.path + "/"
        guard !standardizedDestination.path.hasPrefix(sourcePrefix),
              standardizedDestination != document.rootURL.standardizedFileURL else {
            throw SoundPackError.unsafePath(standardizedDestination.path)
        }

        let parent = standardizedDestination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: standardizedDestination.path) {
            let values = try standardizedDestination.resourceValues(forKeys: [
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ])
            guard values.isSymbolicLink != true, values.isAliasFile != true else {
                throw SoundPackError.unsafeFile(standardizedDestination.path)
            }
        }

        let staging = parent.appendingPathComponent(
            ".simuboard-export-\(UUID().uuidString).simuboardpack",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        var shouldRemoveStaging = true
        defer {
            if shouldRemoveStaging { try? fileManager.removeItem(at: staging) }
        }

        let manifestData = try SoundPackCoding.encode(document.manifest)
        try manifestData.write(
            to: staging.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        for asset in document.manifest.assets.values {
            let source = try document.assetURL(for: asset.id)
            let target = try SoundPackFileUtilities.descendantURL(
                for: asset.relativePath,
                under: staging
            )
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: target)
        }
        let licenses = try SoundPackPackageValidator.licenseFiles(
            at: document.rootURL,
            fileManager: fileManager
        )
        for (relativeName, source) in licenses {
            let target = try SoundPackFileUtilities.descendantURL(
                for: "licenses/\(relativeName)",
                under: staging
            )
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: target)
        }

        _ = try SoundPackPackageValidator.validatePackage(
            at: staging,
            limits: limits,
            fileManager: fileManager
        )
        do {
            if fileManager.fileExists(atPath: standardizedDestination.path) {
                _ = try fileManager.replaceItemAt(
                    standardizedDestination,
                    withItemAt: staging,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try fileManager.moveItem(at: staging, to: standardizedDestination)
            }
            shouldRemoveStaging = false
            return standardizedDestination
        } catch {
            throw SoundPackError.fileOperation(error.localizedDescription)
        }
    }
}
