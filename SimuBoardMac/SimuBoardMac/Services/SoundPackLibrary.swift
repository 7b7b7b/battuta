import Foundation

actor SoundPackLibrary {
    private let fileManager: FileManager
    private let limits: SoundPackValidationLimits
    private let builtInDescriptors: [SoundPackDescriptor]
    let rootURL: URL

    init(
        rootURL: URL? = nil,
        builtInDescriptors: [SoundPackDescriptor] = SoundPackDescriptor.bundledDefaults,
        limits: SoundPackValidationLimits = .standard,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.limits = limits
        self.builtInDescriptors = builtInDescriptors
        self.rootURL = rootURL ?? Self.defaultRootURL(fileManager: fileManager)
    }

    func descriptors() throws -> [SoundPackDescriptor] {
        try ensureRootDirectory()
        let candidates = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        var custom: [SoundPackDescriptor] = []
        for candidate in candidates where candidate.pathExtension.lowercased() == "simuboardpack" {
            guard let packID = UUID(uuidString: candidate.deletingPathExtension().lastPathComponent) else {
                continue
            }
            do {
                custom.append(try loadCustomPack(id: packID).descriptor)
            } catch {
                // A corrupt local pack must not hide the rest of the library.
                continue
            }
        }
        custom.sort { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return builtInDescriptors + custom
    }

    func descriptor(for selectionID: String) throws -> SoundPackDescriptor? {
        try descriptors().first { $0.id == selectionID }
    }

    func containsCustomPack(id: UUID) -> Bool {
        fileManager.fileExists(atPath: packURL(id: id).path)
    }

    func packURL(id: UUID) -> URL {
        rootURL.appendingPathComponent(
            "\(id.uuidString.lowercased()).simuboardpack",
            isDirectory: true
        )
    }

    func loadCustomPack(id: UUID) throws -> SoundPackDocument {
        let url = packURL(id: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SoundPackError.packNotFound(id)
        }
        let manifest = try SoundPackPackageValidator.validatePackage(
            at: url,
            limits: limits,
            fileManager: fileManager
        )
        guard manifest.id == id else {
            throw SoundPackError.invalidManifest("目录 ID 与 manifest ID 不一致")
        }
        return SoundPackDocument(
            descriptor: .custom(manifest: manifest),
            manifest: manifest,
            rootURL: url
        )
    }

    /// Resolves an imported pack's collision policy and installs it in one
    /// actor-isolated operation so concurrent imports cannot race between a
    /// separate `contains` check and `save`.
    @discardableResult
    func saveImported(
        manifest sourceManifest: SoundPackManifest,
        assetFiles: [SoundPackAssetID: URL],
        licenseFiles: [String: URL],
        collisionPolicy: SoundPackImportCollisionPolicy
    ) throws -> SoundPackDescriptor {
        var manifest = sourceManifest
        if containsCustomPack(id: manifest.id) {
            switch collisionPolicy {
            case .duplicate:
                repeat { manifest.id = UUID() } while containsCustomPack(id: manifest.id)
                let now = Date()
                manifest.createdAt = now
                manifest.modifiedAt = now
            case .replace:
                break
            case .reject:
                throw SoundPackError.packAlreadyExists(manifest.id)
            }
        }

        return try save(
            manifest: manifest,
            assetFiles: assetFiles,
            licenseFiles: licenseFiles
        )
    }

    @discardableResult
    func save(
        manifest sourceManifest: SoundPackManifest,
        assetFiles: [SoundPackAssetID: URL] = [:],
        licenseFiles: [String: URL] = [:]
    ) throws -> SoundPackDescriptor {
        try ensureRootDirectory()

        var manifest = sourceManifest
        manifest.modifiedAt = Date()
        try SoundPackValidator.validate(manifest, limits: limits)

        let destination = packURL(id: manifest.id)
        let previousExists = fileManager.fileExists(atPath: destination.path)
        if previousExists {
            _ = try SoundPackPackageValidator.validatePackage(
                at: destination,
                limits: limits,
                fileManager: fileManager
            )
        }

        let staging = rootURL.appendingPathComponent(
            ".staging-\(manifest.id.uuidString)-\(UUID().uuidString).simuboardpack",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        var shouldRemoveStaging = true
        defer {
            if shouldRemoveStaging { try? fileManager.removeItem(at: staging) }
        }

        let assetsDirectory = staging.appendingPathComponent("assets", isDirectory: true)
        try fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

        for asset in manifest.assets.values.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            let sourceURL: URL
            if let supplied = assetFiles[asset.id] {
                sourceURL = supplied
            } else if previousExists {
                sourceURL = try SoundPackFileUtilities.descendantURL(
                    for: asset.relativePath,
                    under: destination
                )
            } else {
                throw SoundPackError.missingAsset(asset.id.rawValue)
            }

            let info = try AudioImportService.validateNormalizedAudio(at: sourceURL, limits: limits)
            let hash = try SoundPackFileUtilities.sha256(of: sourceURL)
            guard hash == asset.sha256,
                  info.byteCount == asset.byteCount,
                  abs(info.durationSeconds - asset.durationSeconds) < 0.002 else {
                throw SoundPackError.hashMismatch(asset.relativePath)
            }
            let targetURL = try SoundPackFileUtilities.descendantURL(
                for: asset.relativePath,
                under: staging
            )
            try fileManager.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        }

        if !licenseFiles.isEmpty {
            try copySuppliedLicenses(licenseFiles, to: staging)
        } else if previousExists {
            try copyExistingLicenses(from: destination, to: staging)
        }

        let manifestData = try SoundPackCoding.encode(manifest)
        guard Int64(manifestData.count) <= limits.maximumManifestBytes else {
            throw SoundPackError.sizeLimitExceeded("manifest.json 过大")
        }
        try manifestData.write(
            to: staging.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )

        _ = try SoundPackPackageValidator.validatePackage(
            at: staging,
            limits: limits,
            fileManager: fileManager
        )

        do {
            if previousExists {
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: staging,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try fileManager.moveItem(at: staging, to: destination)
            }
            shouldRemoveStaging = false
        } catch {
            throw SoundPackError.fileOperation(error.localizedDescription)
        }
        return .custom(manifest: manifest)
    }

    @discardableResult
    func removeCustomPack(id: UUID) throws -> URL {
        try ensureRootDirectory()
        let source = packURL(id: id)
        guard fileManager.fileExists(atPath: source.path) else {
            throw SoundPackError.packNotFound(id)
        }
        _ = try SoundPackPackageValidator.validatePackage(
            at: source,
            limits: limits,
            fileManager: fileManager
        )

        let trash = rootURL.appendingPathComponent(".Trash", isDirectory: true)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        let destination = trash.appendingPathComponent(
            "\(id.uuidString.lowercased())-\(UUID().uuidString).simuboardpack",
            isDirectory: true
        )
        do {
            try fileManager.moveItem(at: source, to: destination)
            return destination
        } catch {
            throw SoundPackError.fileOperation(error.localizedDescription)
        }
    }

    private func ensureRootDirectory() throws {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let values = try rootURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ])
            guard values.isDirectory == true,
                  values.isSymbolicLink != true,
                  values.isAliasFile != true else {
                throw SoundPackError.unsafeFile(rootURL.path)
            }
        } catch let error as SoundPackError {
            throw error
        } catch {
            throw SoundPackError.fileOperation(error.localizedDescription)
        }
    }

    private func copySuppliedLicenses(
        _ licenses: [String: URL],
        to staging: URL
    ) throws {
        for (relativeName, source) in licenses {
            let relativePath = "licenses/\(relativeName)"
            try SoundPackFileUtilities.validateRelativePath(relativePath)
            let byteCount = try SoundPackFileUtilities.validateRegularFile(at: source)
            guard byteCount <= limits.maximumAssetBytes else {
                throw SoundPackError.sizeLimitExceeded(relativePath)
            }
            let target = try SoundPackFileUtilities.descendantURL(
                for: relativePath,
                under: staging
            )
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: target)
        }
    }

    private func copyExistingLicenses(from current: URL, to staging: URL) throws {
        let source = current.appendingPathComponent("licenses", isDirectory: true)
        guard fileManager.fileExists(atPath: source.path) else { return }
        let values = try source.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
        ])
        guard values.isDirectory == true,
              values.isSymbolicLink != true,
              values.isAliasFile != true else {
            throw SoundPackError.unsafeFile(source.path)
        }
        try fileManager.copyItem(
            at: source,
            to: staging.appendingPathComponent("licenses", isDirectory: true)
        )
    }

    private static func defaultRootURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("SimuBoard", isDirectory: true)
            .appendingPathComponent("SoundPacks", isDirectory: true)
    }
}
