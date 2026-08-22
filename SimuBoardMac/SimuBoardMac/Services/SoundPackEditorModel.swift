import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum SoundPackEditorMappingMode: String, CaseIterable, Identifiable, Sendable {
    case generic
    case recommended
    case perKey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .generic: "通用"
        case .recommended: "推荐分布"
        case .perKey: "单键"
        }
    }
}

extension KeyboardRowID {
    var diyDisplayName: String {
        switch self {
        case .r0: "R1 · 数字行"
        case .r1: "R2 · Q 行"
        case .r2: "R3 · A 行"
        case .r3: "R4 · Z 行"
        case .r4: "功能 / 其他键"
        }
    }

    var diyShortName: String {
        switch self {
        case .r0: "R1"
        case .r1: "R2"
        case .r2: "R3"
        case .r3: "R4"
        case .r4: "其他"
        }
    }
}

enum SoundPackEditorSlot: Hashable, Sendable {
    case generic
    case row(KeyboardRowID)
    case special(KeyboardSpecialKeyID)
    case key(KeyboardKeyID)

    var displayName: String {
        switch self {
        case .generic:
            "所有按键"
        case let .row(row):
            row.diyDisplayName
        case let .special(special):
            special.displayName
        case let .key(keyID):
            KeyboardLayoutCatalog.ansiTKL.keys.first(where: { $0.id == keyID })?.label
                ?? keyID.rawValue
        }
    }
}

struct SoundPackEditorAudioTarget: Hashable, Sendable {
    let slot: SoundPackEditorSlot
    let phase: KeySoundPhase
}

enum SoundPackKeyOverrideChoice: String, CaseIterable, Identifiable, Sendable {
    case inherit
    case silent
    case asset

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inherit: "继承"
        case .silent: "静音"
        case .asset: "自定义"
        }
    }
}

struct SoundPackEditorErrorPresentation: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

struct SoundPackSplitDraft: Identifiable, Sendable {
    let id = UUID()
    let target: SoundPackEditorSlot
    let analysis: AudioSplitAnalysis
}

@MainActor
final class SoundPackEditorModel: ObservableObject {
    typealias LibraryDidChange = @MainActor @Sendable (String?) -> Void
    typealias AudioPreview = @MainActor @Sendable (URL) -> Void

    @Published private(set) var customPacks: [SoundPackDescriptor] = []
    @Published private(set) var selectedPackID: UUID?
    @Published private(set) var manifest: SoundPackManifest?
    @Published var selectedKeyID: KeyboardKeyID = KeyboardKeyID("a")
    @Published var mappingMode: SoundPackEditorMappingMode = .recommended
    @Published var recommendedSlot: SoundPackEditorSlot = .row(.r2)
    @Published var splitDraft: SoundPackSplitDraft?
    @Published private(set) var isDirty = false
    @Published private(set) var isWorking = false
    @Published private(set) var statusMessage: String?
    @Published var errorPresentation: SoundPackEditorErrorPresentation?

    let layout = KeyboardLayoutCatalog.ansiTKL

    private let library: SoundPackLibrary
    private let audioImporter: AudioImportService
    private let audioSplitter: AudioSplitService
    private let archiveService: SoundPackArchiveService
    private let fileManager: FileManager
    private let ownsAudioImporterCache: Bool
    private let initialSelectionID: String
    private let onLibraryDidChange: LibraryDidChange
    private let previewAudioAt: AudioPreview
    /// A unique directory owned by this editor session. Keeping split sources
    /// and the default normalized-audio cache here prevents multiple editor
    /// instances from deleting each other's temporary files.
    let temporaryCacheRootURL: URL
    private var assetURLs: [SoundPackAssetID: URL] = [:]
    private var preparedAudio: [SoundPackAssetID: PreparedSoundPackAudio] = [:]
    private var persistedPackID: UUID?

    init(
        library: SoundPackLibrary,
        initialSelectionID: String,
        audioImporter: AudioImportService? = nil,
        audioSplitter: AudioSplitService = AudioSplitService(),
        archiveService: SoundPackArchiveService = SoundPackArchiveService(),
        temporaryCacheParentURL: URL? = nil,
        fileManager: FileManager = .default,
        onLibraryDidChange: @escaping LibraryDidChange,
        previewAudioAt: @escaping AudioPreview
    ) {
        let cacheParent = temporaryCacheParentURL ?? fileManager.temporaryDirectory
        let cacheRoot = cacheParent.appendingPathComponent(
            "SimuBoardEditor-\(UUID().uuidString)",
            isDirectory: true
        )
        self.library = library
        self.initialSelectionID = initialSelectionID
        self.audioImporter = audioImporter ?? AudioImportService(
            workingDirectory: cacheRoot.appendingPathComponent(
                "NormalizedAudio",
                isDirectory: true
            )
        )
        self.ownsAudioImporterCache = audioImporter == nil
        self.audioSplitter = audioSplitter
        self.archiveService = archiveService
        self.fileManager = fileManager
        self.temporaryCacheRootURL = cacheRoot
        self.onLibraryDidChange = onLibraryDidChange
        self.previewAudioAt = previewAudioAt
    }

    var selectedKey: KeyboardKeyDescriptor? {
        layout.keys.first { $0.id == selectedKeyID }
    }

    var canExport: Bool { persistedPackID != nil }
    var hasDraft: Bool { manifest != nil }
    var hasTemporaryAudioResources: Bool {
        !preparedAudio.isEmpty
            || splitDraft != nil
            || fileManager.fileExists(atPath: temporaryCacheRootURL.path)
    }

    var assetChoices: [SoundPackAudioAsset] {
        guard let manifest else { return [] }
        return manifest.assets.values.sorted { lhs, rhs in
            let left = lhs.originalFilename ?? lhs.id.rawValue
            let right = rhs.originalFilename ?? rhs.id.rawValue
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    func loadInitialState() async {
        guard manifest == nil, !isWorking else { return }
        await performWork(status: "正在载入 DIY 音色…") {
            try await reloadLibraryContents()
            if let packID = Self.customPackID(from: initialSelectionID),
               customPacks.contains(where: { $0.customPackID == packID }) {
                try await loadPackIntoEditor(id: packID)
            } else if let first = customPacks.first?.customPackID {
                try await loadPackIntoEditor(id: first)
            } else {
                try await createDraftBasedOnInitialSelection()
            }
        }
    }

    func reloadLibrary() async {
        guard !isWorking else { return }
        await performWork(status: "正在刷新音色库…") {
            try await reloadLibraryContents()
            statusMessage = nil
        }
    }

    func selectPack(id: UUID) async {
        guard !isWorking else { return }
        await performWork(status: "正在打开音色包…") {
            try await loadPackIntoEditor(id: id)
            statusMessage = nil
        }
    }

    func createBlank() async {
        guard !isWorking else { return }
        await performWork(status: "正在新建空白音色…") {
            await discardTemporaryAudioResources(reportFailure: true)
            installBlankDraft()
        }
    }

    private func installBlankDraft() {
        let now = Date()
        manifest = SoundPackManifest(
            name: "未命名音色",
            family: "DIY",
            tone: "自定义音色",
            createdAt: now,
            modifiedAt: now
        )
        assetURLs = [:]
        persistedPackID = nil
        selectedPackID = nil
        mappingMode = .generic
        isDirty = true
        statusMessage = "已创建空白草稿"
    }

    func createBasedOnCurrent() async {
        guard !isWorking else { return }
        await performWork(status: "正在复制当前音色…") {
            try await createDraftBasedOnInitialSelection()
        }
    }

    func setName(_ value: String) {
        mutateManifest { $0.name = value }
    }

    func setAuthor(_ value: String) {
        mutateManifest { $0.author = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value }
    }

    func setNotes(_ value: String) {
        mutateManifest { $0.notes = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value }
    }

    func save(enableAfterSaving: Bool) async {
        guard !isWorking, var draft = manifest else { return }
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            presentMessage("请先输入音色包名称。", title: "无法保存")
            return
        }
        draft.name = trimmedName
        pruneUnusedAssets(in: &draft)

        await performWork(status: "正在保存音色包…") {
            let files = assetURLs.filter { draft.assets[$0.key.rawValue] != nil }
            let descriptor = try await library.save(manifest: draft, assetFiles: files)
            let savedDocument = try await library.loadCustomPack(id: draft.id)
            manifest = savedDocument.manifest
            assetURLs = try Dictionary(uniqueKeysWithValues: savedDocument.manifest.assets.values.map { asset in
                (asset.id, try savedDocument.assetURL(for: asset.id))
            })
            persistedPackID = draft.id
            selectedPackID = draft.id
            isDirty = false
            await discardTemporaryAudioResources(reportFailure: true)
            let descriptors = try await library.descriptors()
            customPacks = descriptors.filter { !$0.isReadOnly }
            statusMessage = enableAfterSaving ? "已保存并启用 \(descriptor.name)" : "已保存 \(descriptor.name)"
            onLibraryDidChange(enableAfterSaving ? descriptor.id : nil)
        }
    }

    func deleteSelectedPack() async {
        guard !isWorking, let id = persistedPackID else { return }
        await performWork(status: "正在移到废纸篓…") {
            _ = try await library.removeCustomPack(id: id)
            let descriptors = try await library.descriptors()
            customPacks = descriptors.filter { !$0.isReadOnly }
            onLibraryDidChange(nil)
            if let nextID = customPacks.first?.customPackID {
                try await loadPackIntoEditor(id: nextID)
            } else {
                await discardTemporaryAudioResources(reportFailure: true)
                installBlankDraft()
            }
            statusMessage = "音色包已移入 Battuta 的可恢复废纸篓"
        }
    }

    func importPack(from sourceURL: URL) async {
        guard !isWorking else { return }
        await withSecurityScopedAccess(to: sourceURL) {
            await performWork(status: "正在导入音色包…") {
                let descriptor = try await archiveService.importPack(
                    at: sourceURL,
                    into: library,
                    collisionPolicy: .duplicate
                )
                guard let id = descriptor.customPackID else {
                    throw SoundPackError.invalidManifest("导入结果不是自定义音色包")
                }
                let descriptors = try await library.descriptors()
                customPacks = descriptors.filter { !$0.isReadOnly }
                let document = try await library.loadCustomPack(id: id)
                try Task.checkCancellation()
                let urls = try Self.assetURLs(for: document)
                await discardTemporaryAudioResources(reportFailure: true)
                manifest = document.manifest
                assetURLs = urls
                persistedPackID = id
                selectedPackID = id
                isDirty = false
                statusMessage = "已导入 \(descriptor.name)"
                onLibraryDidChange(nil)
            }
        }
    }

    func exportSelectedPack() async {
        guard !isWorking, !isDirty, let id = persistedPackID, let manifest else { return }
        let panel = NSSavePanel()
        panel.title = "导出 Battuta 音色包"
        panel.nameFieldStringValue = Self.safeFilename(manifest.name) + ".simuboardpack"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.simuBoardSoundPack]
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        await performWork(status: "正在导出音色包…") {
            let exported = try await archiveService.export(
                customPackID: id,
                from: library,
                to: destination
            )
            statusMessage = "已导出到 \(exported.lastPathComponent)"
        }
    }

    func importAudio(from sourceURL: URL, target: SoundPackEditorAudioTarget) async {
        guard !isWorking, manifest != nil else { return }
        await withSecurityScopedAccess(to: sourceURL) {
            await performWork(status: "正在转换音频…") {
                let prepared = try await audioImporter.prepareImport(from: sourceURL)
                install(prepared: prepared, target: target)
                statusMessage = "已导入 \(sourceURL.lastPathComponent)"
            }
        }
    }

    func analyzeFullKeystroke(from sourceURL: URL, target: SoundPackEditorSlot) async {
        guard !isWorking, manifest != nil else { return }
        await withSecurityScopedAccess(to: sourceURL) {
            await performWork(status: "正在分析按下与回弹…") {
                let localSourceURL = try makeLocalSplitSourceCopy(from: sourceURL)
                do {
                    let analysis = try await audioSplitter.analyze(sourceURL: localSourceURL)
                    splitDraft = SoundPackSplitDraft(target: target, analysis: analysis)
                    statusMessage = nil
                } catch {
                    try? FileManager.default.removeItem(
                        at: localSourceURL.deletingLastPathComponent()
                    )
                    throw error
                }
            }
        }
    }

    @discardableResult
    func confirmSplit(
        draft: SoundPackSplitDraft,
        splitTime: TimeInterval,
        releaseEndTime: TimeInterval
    ) async -> Bool {
        guard !isWorking, manifest != nil else { return false }
        var succeeded = false
        await performWork(status: "正在生成两段音频…") {
            let directory = try makeTemporaryDirectory(prefix: "SplitExport")
            let pressURL = directory.appendingPathComponent("press.wav")
            let releaseURL = directory.appendingPathComponent("release.wav")
            defer { try? fileManager.removeItem(at: directory) }
            _ = try await audioSplitter.exportSplit(
                sourceURL: draft.analysis.sourceURL,
                splitTime: splitTime,
                releaseEndTime: releaseEndTime,
                pressDestination: pressURL,
                releaseDestination: releaseURL
            )
            let press = try await audioImporter.prepareImport(from: pressURL)
            preparedAudio[press.id] = press
            let release = try await audioImporter.prepareImport(from: releaseURL)
            preparedAudio[release.id] = release
            install(
                prepared: press,
                target: SoundPackEditorAudioTarget(slot: draft.target, phase: .press)
            )
            install(
                prepared: release,
                target: SoundPackEditorAudioTarget(slot: draft.target, phase: .release)
            )
            splitDraft = nil
            discardSplitSource(for: draft)
            statusMessage = "已拆分并设置按下/回弹音"
            succeeded = true
        }
        return succeeded
    }

    func previewSplit(
        draft: SoundPackSplitDraft,
        splitTime: TimeInterval,
        releaseEndTime: TimeInterval,
        phase: KeySoundPhase
    ) async {
        guard !isWorking else { return }
        await performWork(status: "正在准备试听…") {
            let directory = try makeTemporaryDirectory(prefix: "SplitPreview")
            let pressURL = directory.appendingPathComponent("press.wav")
            let releaseURL = directory.appendingPathComponent("release.wav")
            defer { try? fileManager.removeItem(at: directory) }
            _ = try await audioSplitter.exportSplit(
                sourceURL: draft.analysis.sourceURL,
                splitTime: splitTime,
                releaseEndTime: releaseEndTime,
                pressDestination: pressURL,
                releaseDestination: releaseURL
            )
            previewAudioAt(phase == .press ? pressURL : releaseURL)
            statusMessage = nil
        }
    }

    func cancelSplit() {
        if let splitDraft { discardSplitSource(for: splitDraft) }
        splitDraft = nil
    }

    func discardSplitSource(for draft: SoundPackSplitDraft) {
        let directory = draft.analysis.sourceURL.deletingLastPathComponent()
        guard directory.lastPathComponent.hasPrefix("SplitSource-") else { return }
        let root = temporaryCacheRootURL.standardizedFileURL
        let candidate = directory.standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(prefix) else { return }
        try? fileManager.removeItem(at: directory)
    }

    func reportFileSelectionError(_ error: Error) {
        present(error, title: "无法读取所选文件")
    }

    func assignmentAsset(for slot: SoundPackEditorSlot, phase: KeySoundPhase) -> SoundPackAssetID? {
        guard let manifest else { return nil }
        let assignments = manifest.assignments(for: phase)
        switch slot {
        case .generic:
            return assignments.generic
        case let .row(row):
            return assignments.asset(for: row)
        case let .special(special):
            return assignments.asset(for: special)
        case let .key(keyID):
            guard case let .asset(assetID)? = assignments.override(for: keyID) else { return nil }
            return assetID
        }
    }

    func overrideChoice(for keyID: KeyboardKeyID, phase: KeySoundPhase) -> SoundPackKeyOverrideChoice {
        guard let manifest else { return .inherit }
        switch manifest.assignments(for: phase).override(for: keyID) {
        case .some(.silent):
            return .silent
        case .some(.asset):
            return .asset
        case .some(.inherit), .none:
            return .inherit
        }
    }

    func setOverrideChoice(
        _ choice: SoundPackKeyOverrideChoice,
        for keyID: KeyboardKeyID,
        phase: KeySoundPhase
    ) {
        mutateAssignments(for: phase) { assignments in
            switch choice {
            case .inherit:
                assignments.setOverride(nil, for: keyID)
            case .silent:
                assignments.setOverride(.silent, for: keyID)
            case .asset:
                if case .asset = assignments.override(for: keyID) { return }
                assignments.setOverride(.inherit, for: keyID)
            }
        }
    }

    func setExistingAsset(
        _ assetID: SoundPackAssetID?,
        slot: SoundPackEditorSlot,
        phase: KeySoundPhase
    ) {
        mutateAssignments(for: phase) { assignments in
            Self.set(assetID: assetID, slot: slot, assignments: &assignments)
        }
    }

    func assetLabel(_ assetID: SoundPackAssetID?) -> String {
        guard let assetID, let asset = manifest?.assets[assetID.rawValue] else { return "继承上一级" }
        return asset.originalFilename ?? String(assetID.rawValue.prefix(10))
    }

    func preview(slot: SoundPackEditorSlot, phase: KeySoundPhase) {
        guard let keyCode = representativeKeyCode(for: slot) else { return }
        preview(keyCode: keyCode, phase: phase)
    }

    func preview(keyCode: UInt16, phase: KeySoundPhase) {
        guard let manifest else { return }
        let resolution = SoundPackResolver(manifest: manifest).resolution(for: keyCode, phase: phase)
        switch resolution {
        case let .asset(assetID, _):
            guard let url = assetURLs[assetID] else { return }
            previewAudioAt(url)
        case .silent:
            return
        case .missing:
            guard let profileID = manifest.baseProfileID,
                  let profile = SwitchProfile(rawValue: profileID),
                  let sample = KeySoundMapper.sample(for: keyCode, phase: phase, profile: profile),
                  let url = Self.bundledURL(profile: profile, phase: phase, sample: sample) else { return }
            previewAudioAt(url)
        }
    }

    func representativeKeyCode(for slot: SoundPackEditorSlot) -> UInt16? {
        switch slot {
        case .generic:
            return 0
        case let .row(row):
            return layout.keys.first(where: { $0.row == row && $0.specialKey == nil })?.keyCode
        case let .special(special):
            return layout.keys.first(where: { $0.specialKey == special })?.keyCode
        case let .key(keyID):
            return layout.keys.first(where: { $0.id == keyID })?.keyCode
        }
    }

    private func install(prepared: PreparedSoundPackAudio, target: SoundPackEditorAudioTarget) {
        guard var draft = manifest else { return }
        draft.assets[prepared.id.rawValue] = prepared.metadata
        var assignments = draft.assignments(for: target.phase)
        Self.set(assetID: prepared.id, slot: target.slot, assignments: &assignments)
        draft.setAssignments(assignments, for: target.phase)
        draft.modifiedAt = Date()
        manifest = draft
        assetURLs[prepared.id] = prepared.normalizedFileURL
        preparedAudio[prepared.id] = prepared
        isDirty = true
    }

    private static func set(
        assetID: SoundPackAssetID?,
        slot: SoundPackEditorSlot,
        assignments: inout SoundPackPhaseAssignments
    ) {
        switch slot {
        case .generic:
            assignments.generic = assetID
        case let .row(row):
            assignments.setAsset(assetID, for: row)
        case let .special(special):
            assignments.setAsset(assetID, for: special)
        case let .key(keyID):
            assignments.setOverride(assetID.map(SoundPackKeyOverride.asset) ?? .inherit, for: keyID)
        }
    }

    private func mutateManifest(_ mutation: (inout SoundPackManifest) -> Void) {
        guard var draft = manifest else { return }
        mutation(&draft)
        draft.modifiedAt = Date()
        manifest = draft
        isDirty = true
    }

    private func mutateAssignments(
        for phase: KeySoundPhase,
        _ mutation: (inout SoundPackPhaseAssignments) -> Void
    ) {
        mutateManifest { draft in
            var assignments = draft.assignments(for: phase)
            mutation(&assignments)
            draft.setAssignments(assignments, for: phase)
        }
    }

    private func pruneUnusedAssets(in draft: inout SoundPackManifest) {
        let referenced = draft.referencedAssetIDs
        draft.assets = draft.assets.filter { referenced.contains(SoundPackAssetID($0.key)) }
    }

    /// Removes resources created for this editor session. The default importer
    /// owns a unique cache and can remove it atomically. An injected importer is
    /// treated as externally owned, so only files returned to this editor are
    /// discarded; this keeps dependency injection safe for tests.
    @discardableResult
    private func discardTemporaryAudioResources(reportFailure: Bool) async -> Bool {
        splitDraft = nil
        var firstError: Error?

        if ownsAudioImporterCache {
            do {
                try await audioImporter.removeAllPreparedAudio()
                preparedAudio.removeAll()
            } catch {
                firstError = error
            }
        } else {
            let trackedAudio = preparedAudio
            for (assetID, prepared) in trackedAudio {
                do {
                    try await audioImporter.discardPreparedAudio(prepared)
                    preparedAudio.removeValue(forKey: assetID)
                } catch {
                    if firstError == nil { firstError = error }
                }
            }
        }

        do {
            if fileManager.fileExists(atPath: temporaryCacheRootURL.path) {
                try fileManager.removeItem(at: temporaryCacheRootURL)
            }
        } catch {
            if firstError == nil { firstError = error }
        }

        if let firstError, reportFailure {
            present(firstError, title: "无法清理临时音频")
        }
        return firstError == nil
    }

    /// Called before closing the editor or allowing the application to quit.
    /// A failed cleanup keeps the editor open so the user never gets a silent
    /// cache leak and can retry after the filesystem issue is resolved.
    func prepareForClosing() async -> Bool {
        guard !isWorking else { return false }
        guard hasTemporaryAudioResources else { return true }

        isWorking = true
        statusMessage = "正在清理临时音频…"
        defer { isWorking = false }
        let succeeded = await discardTemporaryAudioResources(reportFailure: true)
        if succeeded { statusMessage = nil }
        return succeeded
    }

    private func reloadLibraryContents() async throws {
        let descriptors = try await library.descriptors()
        try Task.checkCancellation()
        customPacks = descriptors.filter { !$0.isReadOnly }
    }

    private func loadPackIntoEditor(id: UUID) async throws {
        let document = try await library.loadCustomPack(id: id)
        try Task.checkCancellation()
        let urls = try Self.assetURLs(for: document)
        await discardTemporaryAudioResources(reportFailure: true)
        manifest = document.manifest
        assetURLs = urls
        persistedPackID = id
        selectedPackID = id
        isDirty = false
    }

    private func createDraftBasedOnInitialSelection() async throws {
        if let sourceID = Self.customPackID(from: initialSelectionID) {
            do {
                let document = try await library.loadCustomPack(id: sourceID)
                try Task.checkCancellation()
                var copy = document.manifest
                let now = Date()
                copy.id = UUID()
                copy.name = "\(copy.name) 副本"
                copy.createdAt = now
                copy.modifiedAt = now
                let urls = try Self.assetURLs(for: document)
                await discardTemporaryAudioResources(reportFailure: true)
                manifest = copy
                assetURLs = urls
                persistedPackID = nil
                selectedPackID = nil
                isDirty = true
                statusMessage = "已基于当前音色创建草稿"
                return
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                present(error, title: "无法复制当前音色")
            }
        }

        await discardTemporaryAudioResources(reportFailure: true)
        let baseProfile = SwitchProfile(rawValue: initialSelectionID) ?? .holyPanda
        let now = Date()
        manifest = SoundPackManifest(
            name: "\(baseProfile.displayName) DIY",
            family: baseProfile.family,
            tone: baseProfile.tone,
            baseProfileID: baseProfile.rawValue,
            createdAt: now,
            modifiedAt: now
        )
        assetURLs = [:]
        persistedPackID = nil
        selectedPackID = nil
        mappingMode = .recommended
        isDirty = true
        statusMessage = "未设置的位置会继承 \(baseProfile.displayName)"
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        try fileManager.createDirectory(
            at: temporaryCacheRootURL,
            withIntermediateDirectories: true
        )
        let directory = temporaryCacheRootURL.appendingPathComponent(
            "\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func performWork(
        status: String,
        operation: @MainActor () async throws -> Void
    ) async {
        isWorking = true
        statusMessage = status
        defer { isWorking = false }
        do {
            try await operation()
        } catch is CancellationError {
            statusMessage = nil
        } catch {
            statusMessage = nil
            present(error)
        }
    }

    private func withSecurityScopedAccess(
        to url: URL,
        operation: @MainActor () async -> Void
    ) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        await operation()
    }

    private func present(_ error: Error, title: String = "操作失败") {
        presentMessage(error.localizedDescription, title: title)
    }

    private func presentMessage(_ message: String, title: String) {
        errorPresentation = SoundPackEditorErrorPresentation(title: title, message: message)
    }

    private static func customPackID(from selectionID: String) -> UUID? {
        let prefix = "custom:"
        guard selectionID.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(selectionID.dropFirst(prefix.count)))
    }

    private static func bundledURL(
        profile: SwitchProfile,
        phase: KeySoundPhase,
        sample: KeySoundSample
    ) -> URL? {
        let directory = "Audio/\(profile.rawValue)/\(phase.rawValue)"
        return ["wav", "mp3"].lazy.compactMap { fileExtension in
            Bundle.main.url(
                forResource: sample.rawValue,
                withExtension: fileExtension,
                subdirectory: directory
            )
        }.first
    }

    private func makeLocalSplitSourceCopy(from sourceURL: URL) throws -> URL {
        let directory = try makeTemporaryDirectory(prefix: "SplitSource")
        let fileExtension = sourceURL.pathExtension.isEmpty ? "audio" : sourceURL.pathExtension
        let destination = directory.appendingPathComponent("source.\(fileExtension)")
        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    private static func assetURLs(
        for document: SoundPackDocument
    ) throws -> [SoundPackAssetID: URL] {
        try Dictionary(uniqueKeysWithValues: document.manifest.assets.values.map { asset in
            (asset.id, try document.assetURL(for: asset.id))
        })
    }

    private static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Battuta-Sound-Pack" : cleaned
    }
}

extension UTType {
    static let simuBoardSoundPack = UTType(exportedAs: "com.simuboard.soundpack", conformingTo: .package)
}
