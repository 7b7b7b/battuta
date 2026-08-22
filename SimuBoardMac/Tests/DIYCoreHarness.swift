import AVFAudio
import Darwin
import Foundation

private enum HarnessFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case let .assertion(message): message
        }
    }
}

private struct HarnessResults {
    private(set) var passed = 0

    mutating func check(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard condition() else {
            throw HarnessFailure.assertion("\(file):\(line): \(message)")
        }
        passed += 1
    }

    mutating func expectError(
        _ message: String,
        _ operation: () throws -> Void,
        matches: (Error) -> Bool
    ) throws {
        do {
            try operation()
            throw HarnessFailure.assertion("Expected error: \(message)")
        } catch let failure as HarnessFailure {
            throw failure
        } catch {
            guard matches(error) else {
                throw HarnessFailure.assertion("Wrong error for \(message): \(error)")
            }
            passed += 1
        }
    }
}

private final class LockedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }
}

private actor FetchRecorder {
    private(set) var etags: [String?] = []
    private var responses: [Result<GitHubReleaseFetchResult, Error>]

    init(_ responses: [Result<GitHubReleaseFetchResult, Error>]) {
        self.responses = responses
    }

    func fetch(etag: String?) throws -> GitHubReleaseFetchResult {
        etags.append(etag)
        guard !responses.isEmpty else {
            throw GitHubReleaseClientError.invalidResponse
        }
        return try responses.removeFirst().get()
    }

    var callCount: Int { etags.count }
}

@main
private struct DIYCoreHarness {
    static func main() async {
        var results = HarnessResults()
        do {
            try testSemanticVersion(&results)
            try testValidatorAndResolver(&results)
            try await testAudioLibraryAndArchive(&results)
            try await testAudioSplit(&results)
            try testEngineLoadFailureContract(&results)
            try await testUpdateCachingAndThrottling(&results)
            print("DIY core harness passed: \(results.passed) assertions")
        } catch {
            fputs("DIY core harness FAILED: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func testSemanticVersion(_ results: inout HarnessResults) throws {
        let ordered = [
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-alpha.beta",
            "1.0.0-beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0",
        ].compactMap(SemanticVersion.init)
        try results.check(ordered.count == 8, "all SemVer precedence fixtures should parse")
        try results.check(zip(ordered, ordered.dropFirst()).allSatisfy(<), "SemVer precedence must match 2.0.0")
        try results.check(SemanticVersion("v0.4.0")?.description == "0.4.0", "release tag prefix should parse")
        try results.check(
            SemanticVersion("1.2.3+build.1") == SemanticVersion("1.2.3+build.2"),
            "build metadata must not affect precedence equality"
        )

        for invalid in ["1.2", "01.2.3", "1.02.3", "1.2.03", "1.2.3-01", "1.2.3-", "1.2.3+", "1.2.3+bad_idea"] {
            try results.check(SemanticVersion(invalid) == nil, "invalid SemVer accepted: \(invalid)")
        }
    }

    private static func testValidatorAndResolver(_ results: inout HarnessResults) throws {
        let overrideID = soundAssetID("a")
        let specialID = soundAssetID("b")
        let rowID = soundAssetID("c")
        let genericID = soundAssetID("d")
        let assets = Dictionary(uniqueKeysWithValues: [overrideID, specialID, rowID, genericID].map {
            ($0.rawValue, fakeAsset(id: $0))
        })

        var press = SoundPackPhaseAssignments(generic: genericID)
        press.setAsset(rowID, for: .r2)
        press.setAsset(specialID, for: .space)
        press.setOverride(.asset(overrideID), for: KeyboardKeyID("a"))
        var manifest = SoundPackManifest(
            name: "Resolver fixture",
            baseProfileID: SwitchProfile.mxBlue.rawValue,
            press: press,
            assets: assets
        )
        try SoundPackValidator.validate(manifest)
        var resolver = SoundPackResolver(manifest: manifest)

        try results.check(
            resolver.resolution(for: 0, phase: .press) == .asset(overrideID, source: .keyOverride(KeyboardKeyID("a"))),
            "per-key override must beat row and generic"
        )
        try results.check(
            resolver.resolution(for: 49, phase: .press) == .asset(specialID, source: .special(.space)),
            "special assignment must beat row and generic"
        )
        try results.check(
            resolver.resolution(for: 1, phase: .press) == .asset(rowID, source: .row(.r2)),
            "row assignment must beat generic"
        )
        try results.check(
            resolver.resolution(for: 12, phase: .press) == .asset(genericID, source: .generic),
            "generic assignment should be the final custom fallback"
        )

        manifest.press.setOverride(.inherit, for: KeyboardKeyID("a"))
        resolver = SoundPackResolver(manifest: manifest)
        try results.check(
            resolver.resolution(for: 0, phase: .press) == .asset(rowID, source: .row(.r2)),
            "inherit must continue resolving through row"
        )

        manifest.press.setOverride(.silent, for: KeyboardKeyID("a"))
        resolver = SoundPackResolver(manifest: manifest)
        try results.check(
            resolver.resolution(for: 0, phase: .press) == .silent(source: .keyOverride(KeyboardKeyID("a"))),
            "explicit silence must prevent lower-level fallback"
        )
        try results.check(
            resolver.resolution(for: 63, phase: .press) == .asset(genericID, source: .generic),
            "Fn/Globe should participate in DIY mapping when delivered as flagsChanged"
        )

        let fallbackManifest = SoundPackManifest(
            name: "Built-in fallback fixture",
            baseProfileID: SwitchProfile.mxClear.rawValue
        )
        try results.check(
            SoundPackResolver(manifest: fallbackManifest).resolution(for: 0, phase: .press)
                == .missing(source: .missingAssignment),
            "unassigned custom slots must remain missing so the engine can reach the built-in fallback"
        )
        try results.check(
            KeySoundMapper.sample(for: 0, phase: .release, profile: .mxClear) == .genericR2,
            "built-in fallback should retain the base profile's row-specific release mapping"
        )

        var broken = manifest
        broken.assets.removeValue(forKey: overrideID.rawValue)
        broken.press.setOverride(.asset(overrideID), for: KeyboardKeyID("a"))
        try results.check(
            SoundPackResolver(manifest: broken).resolution(for: 0, phase: .press)
                == .missing(source: .brokenAssetReference(overrideID)),
            "resolver must not return an absent asset"
        )

        var missingAsset = manifest
        missingAsset.assets.removeValue(forKey: overrideID.rawValue)
        missingAsset.press.setOverride(.asset(overrideID), for: KeyboardKeyID("a"))
        try results.expectError("validator rejects missing asset", {
            try SoundPackValidator.validate(missingAsset)
        }, matches: {
            if case SoundPackError.missingAsset = $0 { return true }
            return false
        })

        var unknownRow = manifest
        unknownRow.press.rows["R99"] = genericID
        try results.expectError("validator rejects unknown row", {
            try SoundPackValidator.validate(unknownRow)
        }, matches: {
            if case SoundPackError.invalidManifest = $0 { return true }
            return false
        })

        var unsafePath = manifest
        unsafePath.assets[genericID.rawValue]?.relativePath = "../escape.wav"
        try results.expectError("validator rejects traversal path", {
            try SoundPackValidator.validate(unsafePath)
        }, matches: {
            if case SoundPackError.unsafePath = $0 { return true }
            return false
        })

        var unknownBase = manifest
        unknownBase.baseProfileID = "unknown-profile"
        try results.expectError("validator rejects unknown built-in fallback", {
            try SoundPackValidator.validate(unknownBase)
        }, matches: {
            if case SoundPackError.invalidManifest = $0 { return true }
            return false
        })

        var unknownLayout = manifest
        unknownLayout.layoutID = "future-iso-layout"
        try results.expectError("validator rejects unsupported layout", {
            try SoundPackValidator.validate(unknownLayout)
        }, matches: {
            if case SoundPackError.invalidManifest = $0 { return true }
            return false
        })

        var excessiveDuration = SoundPackManifest(name: "Excessive duration")
        for index in 1...37 {
            let rawID = String(format: "%064x", index)
            let id = SoundPackAssetID(rawID)
            excessiveDuration.assets[rawID] = SoundPackAudioAsset(
                id: id,
                relativePath: "assets/\(rawID).wav",
                sha256: rawID,
                durationSeconds: 5,
                byteCount: 480_044
            )
        }
        try results.expectError("validator rejects excessive total audio duration", {
            try SoundPackValidator.validate(excessiveDuration)
        }, matches: {
            if case SoundPackError.sizeLimitExceeded = $0 { return true }
            return false
        })
    }

    private static func testAudioLibraryAndArchive(_ results: inout HarnessResults) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimuBoard-DIYCoreHarness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let boundedPCMBytes = try AudioImportService.checkedDecodedPCMByteCount(
            sampleRate: 48_000,
            channelCount: 2,
            frameLength: 48_000,
            bytesPerSample: 4
        )
        try results.check(boundedPCMBytes == 384_000, "decoded PCM byte count should include every channel")

        let framesAtMemoryLimit = AudioImportService.maximumDecodedPCMBytes / (8 * 8)
        let exactMemoryLimit = try AudioImportService.checkedDecodedPCMByteCount(
            sampleRate: 384_000,
            channelCount: 8,
            frameLength: framesAtMemoryLimit,
            bytesPerSample: 8
        )
        try results.check(
            exactMemoryLimit == AudioImportService.maximumDecodedPCMBytes,
            "decoded PCM allocation should allow the exact 64 MiB boundary"
        )
        try results.expectError("decoded PCM allocation rejects memory amplification", {
            _ = try AudioImportService.checkedDecodedPCMByteCount(
                sampleRate: 384_000,
                channelCount: 8,
                frameLength: framesAtMemoryLimit + 1,
                bytesPerSample: 8
            )
        }, matches: {
            if case SoundPackError.sizeLimitExceeded = $0 { return true }
            return false
        })
        try results.expectError("decoded PCM allocation rejects excessive channels", {
            _ = try AudioImportService.checkedDecodedPCMByteCount(
                sampleRate: 48_000,
                channelCount: 9,
                frameLength: 48_000,
                bytesPerSample: 4
            )
        }, matches: {
            if case SoundPackError.invalidAudio = $0 { return true }
            return false
        })
        try results.expectError("decoded PCM allocation rejects excessive sample rates", {
            _ = try AudioImportService.checkedDecodedPCMByteCount(
                sampleRate: 768_000,
                channelCount: 1,
                frameLength: 48_000,
                bytesPerSample: 4
            )
        }, matches: {
            if case SoundPackError.invalidAudio = $0 { return true }
            return false
        })
        try results.expectError("decoded PCM arithmetic cannot overflow", {
            _ = try AudioImportService.checkedDecodedPCMByteCount(
                sampleRate: 48_000,
                channelCount: 8,
                frameLength: Int64(AVAudioFrameCount.max),
                bytesPerSample: Int.max
            )
        }, matches: {
            if case SoundPackError.sizeLimitExceeded = $0 { return true }
            return false
        })

        let sourceURL = root.appendingPathComponent("source-44k-stereo.wav")
        try makeStereoFixture(at: sourceURL, sampleRate: 44_100, duration: 0.12)

        let importsRoot = root.appendingPathComponent("imports", isDirectory: true)
        let importer = AudioImportService(workingDirectory: importsRoot)
        let prepared = try await importer.prepareImport(from: sourceURL)
        let normalizedInfo = try AudioImportService.validateNormalizedAudio(at: prepared.normalizedFileURL)
        try results.check(normalizedInfo.sampleRate == 48_000, "import must normalize to 48 kHz")
        try results.check(normalizedInfo.channelCount == 1, "import must normalize to mono")
        try results.check(abs(normalizedInfo.durationSeconds - 0.12) < 0.003, "normalization should preserve duration")
        try results.check(prepared.metadata.sha256 == prepared.id.rawValue, "asset ID must be content hash")

        let duplicatePreparation = try await importer.prepareImport(from: sourceURL)
        try results.check(duplicatePreparation.id == prepared.id, "same normalized content should deduplicate")
        try results.check(
            duplicatePreparation.normalizedFileURL == prepared.normalizedFileURL,
            "deduplicated preparations should reuse the normalized file"
        )

        let invalidSourceURL = root.appendingPathComponent("invalid-compressed-audio.mp3")
        try Data("not an audio file".utf8).write(to: invalidSourceURL)

        let timeoutPIDURL = root.appendingPathComponent("timeout-ffmpeg.pid")
        let timeoutExecutableURL = root.appendingPathComponent("timeout-ffmpeg")
        try makeSleepingExecutable(at: timeoutExecutableURL, pidFileURL: timeoutPIDURL)
        let timeoutImportsRoot = root.appendingPathComponent("timeout-imports", isDirectory: true)
        let timeoutImporter = AudioImportService(
            workingDirectory: timeoutImportsRoot,
            ffmpegExecutableOverride: timeoutExecutableURL,
            ffmpegTimeoutSeconds: 0.5
        )
        let timeoutStartedAt = ProcessInfo.processInfo.systemUptime
        do {
            _ = try await timeoutImporter.prepareImport(from: invalidSourceURL)
            throw HarnessFailure.assertion("ffmpeg timeout fixture unexpectedly imported")
        } catch let error as SoundPackError {
            guard case let .invalidAudio(message) = error, message.contains("超时") else {
                throw HarnessFailure.assertion("wrong ffmpeg timeout error: \(error)")
            }
            try results.check(true, "ffmpeg fallback should report a bounded timeout")
        }
        let timeoutElapsed = ProcessInfo.processInfo.systemUptime - timeoutStartedAt
        try results.check(timeoutElapsed < 3, "ffmpeg timeout must return promptly")
        let timeoutPID = try readProcessIdentifier(at: timeoutPIDURL)
        try results.check(!processExists(timeoutPID), "timed-out ffmpeg process must be terminated")
        let timeoutLeftovers = try FileManager.default.contentsOfDirectory(
            at: timeoutImportsRoot,
            includingPropertiesForKeys: nil
        )
        try results.check(timeoutLeftovers.isEmpty, "timed-out ffmpeg output must be removed")

        try FileManager.default.removeItem(at: timeoutPIDURL)
        let playlistURL = root.appendingPathComponent("network-playlist.m3u")
        try Data("https://example.invalid/secret.mp3\n".utf8).write(to: playlistURL)
        do {
            _ = try await timeoutImporter.prepareImport(from: playlistURL)
            throw HarnessFailure.assertion("playlist unexpectedly reached fallback conversion")
        } catch let error as SoundPackError {
            guard case .invalidAudio = error else {
                throw HarnessFailure.assertion("wrong playlist rejection error: \(error)")
            }
            try results.check(true, "ffmpeg fallback should reject playlist containers")
        }
        try results.check(
            !FileManager.default.fileExists(atPath: timeoutPIDURL.path),
            "rejected playlists must not start the external converter"
        )

        let cancellationPIDURL = root.appendingPathComponent("cancelled-ffmpeg.pid")
        let cancellationExecutableURL = root.appendingPathComponent("cancelled-ffmpeg")
        try makeSleepingExecutable(at: cancellationExecutableURL, pidFileURL: cancellationPIDURL)
        let cancellationImportsRoot = root.appendingPathComponent("cancelled-imports", isDirectory: true)
        let cancellationImporter = AudioImportService(
            workingDirectory: cancellationImportsRoot,
            ffmpegExecutableOverride: cancellationExecutableURL,
            ffmpegTimeoutSeconds: 20
        )
        let cancellationTask = Task<PreparedSoundPackAudio, Error> {
            try await cancellationImporter.prepareImport(from: invalidSourceURL)
        }
        let fallbackStarted = await waitForFile(at: cancellationPIDURL, timeoutSeconds: 2)
        guard fallbackStarted else {
            cancellationTask.cancel()
            _ = try? await cancellationTask.value
            throw HarnessFailure.assertion("ffmpeg cancellation fixture did not start")
        }
        let cancellationPID = try readProcessIdentifier(at: cancellationPIDURL)
        let cancellationStartedAt = ProcessInfo.processInfo.systemUptime
        cancellationTask.cancel()
        do {
            _ = try await cancellationTask.value
            throw HarnessFailure.assertion("cancelled ffmpeg import unexpectedly succeeded")
        } catch is CancellationError {
            try results.check(true, "ffmpeg fallback should preserve task cancellation")
        }
        let cancellationElapsed = ProcessInfo.processInfo.systemUptime - cancellationStartedAt
        try results.check(cancellationElapsed < 3, "cancelled ffmpeg import must return promptly")
        try results.check(!processExists(cancellationPID), "cancelled ffmpeg process must be terminated")
        let cancellationLeftovers = try FileManager.default.contentsOfDirectory(
            at: cancellationImportsRoot,
            includingPropertiesForKeys: nil
        )
        try results.check(cancellationLeftovers.isEmpty, "cancelled ffmpeg output must be removed")

        var assignments = SoundPackPhaseAssignments(generic: prepared.id)
        assignments.setAsset(prepared.id, for: .space)
        let packID = UUID()
        let manifest = SoundPackManifest(
            id: packID,
            name: "Round trip",
            baseProfileID: SwitchProfile.holyPanda.rawValue,
            press: assignments,
            release: SoundPackPhaseAssignments(generic: prepared.id),
            assets: [prepared.id.rawValue: prepared.metadata]
        )

        let libraryRoot = root.appendingPathComponent("library", isDirectory: true)
        let library = SoundPackLibrary(rootURL: libraryRoot, builtInDescriptors: [])
        let descriptor = try await library.save(
            manifest: manifest,
            assetFiles: [prepared.id: prepared.normalizedFileURL]
        )
        try results.check(descriptor.customPackID == packID, "save should preserve pack UUID")
        let loaded = try await library.loadCustomPack(id: packID)
        try results.check(loaded.manifest.name == "Round trip", "saved manifest should load")
        let loadedAssetURL = try loaded.assetURL(for: prepared.id)
        let loadedAssetHash = try SoundPackFileUtilities.sha256(of: loadedAssetURL)
        try results.check(
            loadedAssetHash == prepared.id.rawValue,
            "saved audio hash should survive library round trip"
        )
        let initialDescriptors = try await library.descriptors()
        try results.check(initialDescriptors.count == 1, "library should enumerate saved custom pack")

        var renamed = loaded.manifest
        renamed.name = "Round trip renamed"
        _ = try await library.save(manifest: renamed)
        let reloadedAfterRename = try await library.loadCustomPack(id: packID)
        try results.check(
            reloadedAfterRename.manifest.name == "Round trip renamed",
            "updating metadata should retain existing asset files"
        )

        let archive = SoundPackArchiveService()
        let exportURL = root.appendingPathComponent("export.simuboardpack", isDirectory: true)
        _ = try await archive.export(customPackID: packID, from: library, to: exportURL)
        _ = try await archive.validate(at: exportURL)
        try results.check(FileManager.default.fileExists(atPath: exportURL.path), "export should create package")

        // Exporting over an existing package exercises the atomic replacement path.
        _ = try await archive.export(customPackID: packID, from: library, to: exportURL)
        _ = try await archive.validate(at: exportURL)
        try results.check(true, "re-export over an existing package should remain valid")

        let importedLibrary = SoundPackLibrary(
            rootURL: root.appendingPathComponent("imported-library", isDirectory: true),
            builtInDescriptors: []
        )
        let imported = try await archive.importPack(at: exportURL, into: importedLibrary)
        try results.check(imported.customPackID == packID, "first import should retain package UUID")

        do {
            _ = try await archive.importPack(
                at: exportURL,
                into: importedLibrary,
                collisionPolicy: .reject
            )
            throw HarnessFailure.assertion("reject collision policy accepted a duplicate UUID")
        } catch SoundPackError.packAlreadyExists(let rejectedID) {
            try results.check(rejectedID == packID, "reject collision should report colliding UUID")
        }

        let duplicated = try await archive.importPack(
            at: exportURL,
            into: importedLibrary,
            collisionPolicy: .duplicate
        )
        try results.check(duplicated.customPackID != packID, "duplicate collision should mint a new UUID")
        let duplicatedDescriptors = try await importedLibrary.descriptors()
        try results.check(duplicatedDescriptors.count == 2, "duplicate import should preserve both packs")

        let exportedManifestURL = exportURL.appendingPathComponent("manifest.json")
        var replacementManifest = try SoundPackCoding.decode(Data(contentsOf: exportedManifestURL))
        replacementManifest.name = "Collision replacement"
        try SoundPackCoding.encode(replacementManifest).write(to: exportedManifestURL, options: .atomic)
        _ = try await archive.validate(at: exportURL)
        _ = try await archive.importPack(
            at: exportURL,
            into: importedLibrary,
            collisionPolicy: .replace
        )
        let replacedDescriptors = try await importedLibrary.descriptors()
        try results.check(replacedDescriptors.count == 2, "replace collision should not add a third pack")
        let replacedDocument = try await importedLibrary.loadCustomPack(id: packID)
        try results.check(
            replacedDocument.manifest.name == "Collision replacement",
            "replace collision should update the existing package contents"
        )
    }

    private static func testAudioSplit(_ results: inout HarnessResults) async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "SimuBoardSplitHarness-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("complete-keystroke.wav")
        try makeStereoFixture(at: source, sampleRate: 44_100, duration: 0.16)

        let splitter = AudioSplitService()
        let analysis = try await splitter.analyze(sourceURL: source)
        try results.check(analysis.sampleRate == 48_000, "split analysis should normalize to 48 kHz")
        try results.check(analysis.frameCount > 0, "split analysis should produce samples")
        try results.check(
            analysis.suggestion.splitTime > 0 && analysis.suggestion.splitTime < analysis.duration,
            "split suggestion should stay inside the recording"
        )

        let press = root.appendingPathComponent("press.wav")
        let release = root.appendingPathComponent("release.wav")
        let splitTime = analysis.duration / 2
        let exported = try await splitter.exportSplit(
            sourceURL: source,
            splitTime: splitTime,
            releaseEndTime: analysis.duration,
            pressDestination: press,
            releaseDestination: release
        )
        try results.check(exported.pressFrameCount > 0, "press export should not be empty")
        try results.check(exported.releaseFrameCount > 0, "release export should not be empty")
        let pressInfo = try AudioImportService.validateNormalizedAudio(at: press)
        let releaseInfo = try AudioImportService.validateNormalizedAudio(at: release)
        try results.check(pressInfo.sampleRate == 48_000, "press export should be normalized")
        try results.check(releaseInfo.sampleRate == 48_000, "release export should be normalized")

        _ = try await splitter.exportSplit(
            sourceURL: source,
            splitTime: splitTime,
            releaseEndTime: analysis.duration,
            pressDestination: press,
            releaseDestination: release,
            overwriteExisting: true
        )
        try results.check(
            fileManager.fileExists(atPath: press.path) && fileManager.fileExists(atPath: release.path),
            "pair overwrite should leave both outputs installed"
        )

        var constrainedConfiguration = AudioSplitConfiguration()
        constrainedConfiguration.maximumDecodedBytes = 1_024
        let constrained = AudioSplitService(configuration: constrainedConfiguration)
        do {
            _ = try await constrained.analyze(sourceURL: source)
            throw HarnessFailure.assertion("oversized decoded split input should be rejected")
        } catch let error as AudioSplitError {
            guard case .decodedAudioIsTooLarge = error else {
                throw HarnessFailure.assertion("wrong split memory-limit error: \(error)")
            }
            try results.check(true, "split decoded PCM limit should reject oversized input")
        }
    }

    private static func testEngineLoadFailureContract(_ results: inout HarnessResults) throws {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let engineURL = projectRoot.appendingPathComponent(
            "SimuBoardMac/SimuBoardMac/Services/KeyboardAudioEngine.swift"
        )
        let appModelURL = projectRoot.appendingPathComponent(
            "SimuBoardMac/SimuBoardMac/Services/AppModel.swift"
        )
        let engineSource = try String(contentsOf: engineURL, encoding: .utf8)
        let appModelSource = try String(contentsOf: appModelURL, encoding: .utf8)

        try results.check(
            engineSource.contains("func load(document: SoundPackDocument) -> Bool"),
            "custom engine loading must report success/failure"
        )
        guard let loadStart = engineSource.range(of: "func load(document: SoundPackDocument) -> Bool")?.lowerBound,
              let playStart = engineSource.range(of: "    func play(", range: loadStart..<engineSource.endIndex)?.lowerBound else {
            throw HarnessFailure.assertion("could not isolate custom load implementation")
        }
        let customLoadSource = engineSource[loadStart..<playStart]
        let failurePosition = customLoadSource.range(of: "return false")?.lowerBound
        let commitPosition = customLoadSource.range(of: "loadedSelectionID = document.id")?.lowerBound
        try results.check(
            failurePosition != nil && commitPosition != nil && failurePosition! < commitPosition!,
            "custom load should validate resources before committing selection state"
        )
        try results.check(
            appModelSource.contains("if audioEngine.load(document: document)")
                && appModelSource.contains("audioEngine.load(profile: fallback)"),
            "AppModel must detect custom-load failure and perform an explicit fallback"
        )
        try results.check(
            appModelSource.contains("DIY 音色载入失败，已回退到"),
            "fallback should remain visible to the user instead of silently playing the prior pack"
        )
    }

    @MainActor
    private static func testUpdateCachingAndThrottling(_ results: inout HarnessResults) async throws {
        let release = try ReleaseSummary(
            tagName: "v0.4.1",
            releaseURL: URL(string: "https://github.com/7b7b7b/simuboard/releases/tag/v0.4.1")!,
            publishedAt: nil
        )
        let rateLimit = GitHubRateLimit(remaining: 59, resetAt: nil)
        let modified = GitHubReleaseFetchResult.modified(
            release: release,
            etag: "etag-041",
            rateLimit: rateLimit
        )
        let notModified = GitHubReleaseFetchResult.notModified(
            etag: "etag-041",
            rateLimit: rateLimit
        )
        let recorder = FetchRecorder([.success(modified), .success(notModified), .success(notModified)])
        let client = GitHubReleaseClient { etag in try await recorder.fetch(etag: etag) }
        let suiteName = "SimuBoard.DIYCoreHarness.Updates.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw HarnessFailure.assertion("could not create isolated UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let clock = LockedClock(Date(timeIntervalSince1970: 1_800_000_000))
        let installed = SemanticVersion(major: 0, minor: 4, patch: 0)
        let controller = UpdateController(
            client: client,
            installedVersion: installed,
            defaults: defaults,
            now: clock.now
        )
        controller.enableAutomaticChecks(checkImmediately: false)
        await controller.check(trigger: .manual)
        let firstManualCallCount = await recorder.callCount
        try results.check(firstManualCallCount == 1, "first manual check should fetch")
        try results.check(controller.availableRelease?.version == SemanticVersion("0.4.1"), "newer release should surface")

        clock.advance(5)
        await controller.check(trigger: .manual)
        let spacedManualCallCount = await recorder.callCount
        try results.check(spacedManualCallCount == 1, "manual checks within 65 seconds should be suppressed")

        clock.advance(61)
        await controller.check(trigger: .manual)
        let resumedManualCallCount = await recorder.callCount
        try results.check(resumedManualCallCount == 2, "manual check should resume after spacing window")
        let firstControllerETags = await recorder.etags
        try results.check(firstControllerETags.last! == "etag-041", "subsequent fetch should send cached ETag")

        let relaunchedRecorder = FetchRecorder([.success(notModified)])
        let relaunchedClient = GitHubReleaseClient { etag in try await relaunchedRecorder.fetch(etag: etag) }
        let relaunched = UpdateController(
            client: relaunchedClient,
            installedVersion: installed,
            defaults: defaults,
            now: clock.now
        )
        try results.check(relaunched.availableRelease?.version == SemanticVersion("0.4.1"), "cached result should survive relaunch")
        await relaunched.check(trigger: .automatic)
        let cachedAutomaticCallCount = await relaunchedRecorder.callCount
        try results.check(cachedAutomaticCallCount == 0, "successful automatic check cache should live for 24 hours")

        clock.advance(24 * 60 * 60 + 1)
        await relaunched.check(trigger: .automatic)
        let expiredAutomaticCallCount = await relaunchedRecorder.callCount
        try results.check(expiredAutomaticCallCount == 1, "automatic check should resume after TTL")
        let relaunchedETags = await relaunchedRecorder.etags
        try results.check(relaunchedETags == ["etag-041"], "relaunch should retain ETag cache")

        let failureSuite = "SimuBoard.DIYCoreHarness.UpdateFailures.\(UUID().uuidString)"
        guard let failureDefaults = UserDefaults(suiteName: failureSuite) else {
            throw HarnessFailure.assertion("could not create failure UserDefaults")
        }
        defer { failureDefaults.removePersistentDomain(forName: failureSuite) }
        let failureClock = LockedClock(Date(timeIntervalSince1970: 1_900_000_000))
        let failureRecorder = FetchRecorder([
            .failure(URLError(.notConnectedToInternet)),
            .failure(URLError(.notConnectedToInternet)),
        ])
        let failureClient = GitHubReleaseClient { etag in try await failureRecorder.fetch(etag: etag) }
        let failures = UpdateController(
            client: failureClient,
            installedVersion: installed,
            defaults: failureDefaults,
            now: failureClock.now
        )
        failures.enableAutomaticChecks(checkImmediately: false)
        await failures.check(trigger: .automatic)
        let firstFailureCallCount = await failureRecorder.callCount
        try results.check(firstFailureCallCount == 1, "first automatic failure should fetch once")
        failureClock.advance(30 * 60)
        await failures.check(trigger: .automatic)
        let cooldownCallCount = await failureRecorder.callCount
        try results.check(cooldownCallCount == 1, "automatic failures should cool down for one hour")
        failureClock.advance(31 * 60)
        await failures.check(trigger: .automatic)
        let expiredCooldownCallCount = await failureRecorder.callCount
        try results.check(expiredCooldownCallCount == 2, "automatic failure cooldown should expire")

        let limitSuite = "SimuBoard.DIYCoreHarness.UpdateRateLimit.\(UUID().uuidString)"
        guard let limitDefaults = UserDefaults(suiteName: limitSuite) else {
            throw HarnessFailure.assertion("could not create rate-limit UserDefaults")
        }
        defer { limitDefaults.removePersistentDomain(forName: limitSuite) }
        let limitClock = LockedClock(Date(timeIntervalSince1970: 2_000_000_000))
        let retryAt = limitClock.now().addingTimeInterval(120)
        let limitRecorder = FetchRecorder([
            .failure(GitHubReleaseClientError.rateLimited(retryAt: retryAt)),
            .success(modified),
        ])
        let limitClient = GitHubReleaseClient { etag in try await limitRecorder.fetch(etag: etag) }
        let limited = UpdateController(
            client: limitClient,
            installedVersion: installed,
            defaults: limitDefaults,
            now: limitClock.now
        )
        await limited.check(trigger: .manual)
        limitClock.advance(60)
        await limited.check(trigger: .manual)
        let blockedRateLimitCalls = await limitRecorder.callCount
        try results.check(blockedRateLimitCalls == 1, "server retry deadline should block both manual and automatic requests")
        limitClock.advance(61)
        await limited.check(trigger: .manual)
        let resumedRateLimitCalls = await limitRecorder.callCount
        try results.check(resumedRateLimitCalls == 2, "requesting should resume after server retry deadline")

        let exhaustedSuite = "SimuBoard.DIYCoreHarness.UpdateExhausted.\(UUID().uuidString)"
        guard let exhaustedDefaults = UserDefaults(suiteName: exhaustedSuite) else {
            throw HarnessFailure.assertion("could not create exhausted-rate UserDefaults")
        }
        defer { exhaustedDefaults.removePersistentDomain(forName: exhaustedSuite) }
        let exhaustedClock = LockedClock(Date(timeIntervalSince1970: 2_100_000_000))
        let exhaustedReset = exhaustedClock.now().addingTimeInterval(120)
        let exhaustedRecorder = FetchRecorder([
            .success(
                .modified(
                    release: release,
                    etag: "etag-exhausted",
                    rateLimit: GitHubRateLimit(remaining: 0, resetAt: exhaustedReset)
                )
            ),
            .success(notModified),
        ])
        let exhaustedClient = GitHubReleaseClient {
            etag in try await exhaustedRecorder.fetch(etag: etag)
        }
        let exhausted = UpdateController(
            client: exhaustedClient,
            installedVersion: installed,
            defaults: exhaustedDefaults,
            now: exhaustedClock.now
        )
        await exhausted.check(trigger: .manual)
        exhaustedClock.advance(66)
        await exhausted.check(trigger: .manual)
        let proactivelyBlockedCalls = await exhaustedRecorder.callCount
        try results.check(
            proactivelyBlockedCalls == 1,
            "a successful response with zero remaining requests should honor its reset time"
        )
        exhaustedClock.advance(55)
        await exhausted.check(trigger: .manual)
        let proactivelyResumedCalls = await exhaustedRecorder.callCount
        try results.check(
            proactivelyResumedCalls == 2,
            "manual requests should resume after an exhausted successful response resets"
        )
    }

    private static func soundAssetID(_ character: Character) -> SoundPackAssetID {
        SoundPackAssetID(String(repeating: String(character), count: 64))
    }

    private static func fakeAsset(id: SoundPackAssetID) -> SoundPackAudioAsset {
        SoundPackAudioAsset(
            id: id,
            relativePath: "assets/\(id.rawValue).wav",
            sha256: id.rawValue,
            durationSeconds: 0.1,
            byteCount: 9_644
        )
    }

    private static func makeStereoFixture(
        at url: URL,
        sampleRate: Double,
        duration: Double
    ) throws {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else {
            throw HarnessFailure.assertion("could not make source audio format")
        }
        let frameCount = AVAudioFrameCount((sampleRate * duration).rounded())
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            throw HarnessFailure.assertion("could not make source audio buffer")
        }
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            let value = Float(sin(2 * Double.pi * 440 * Double(frame) / sampleRate) * 0.25)
            channels[0][frame] = value
            channels[1][frame] = -value * 0.75
        }
        var outputSettings = format.settings
        outputSettings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(
            forWriting: url,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }

    private static func makeSleepingExecutable(at url: URL, pidFileURL: URL) throws {
        let quotedPIDPath = pidFileURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        #!/bin/sh
        printf '%s' "$$" > '\(quotedPIDPath)'
        exec /bin/sleep 30
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func readProcessIdentifier(at url: URL) throws -> pid_t {
        let contents = try String(contentsOf: url, encoding: .utf8)
        guard let identifier = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)),
              identifier > 0 else {
            throw HarnessFailure.assertion("invalid process identifier fixture")
        }
        return identifier
    }

    private static func processExists(_ identifier: pid_t) -> Bool {
        Darwin.kill(identifier, 0) == 0
    }

    private static func waitForFile(at url: URL, timeoutSeconds: TimeInterval) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeoutSeconds
        while ProcessInfo.processInfo.systemUptime < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
