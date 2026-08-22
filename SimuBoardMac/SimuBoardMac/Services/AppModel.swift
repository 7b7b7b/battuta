import AppKit
import Combine

enum KeyboardMonitoringState: Equatable {
    case stopped
    case waitingForPermission
    case running
    case failed(String)
}

@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let permission: InputMonitoringPermissionManager
    let updates: UpdateController
    let soundPackLibrary: SoundPackLibrary
    @Published private(set) var monitoringState: KeyboardMonitoringState = .stopped
    @Published private(set) var audioError: String?
    @Published private(set) var pointerSoundError: String?
    @Published private(set) var soundPackError: String?
    @Published private(set) var soundPacks: [SoundPackDescriptor] = SoundPackDescriptor.bundledDefaults

    private let audioEngine: KeyboardAudioEngine
    private let keyboardMonitor: KeyboardMonitor
    private var cancellables: Set<AnyCancellable> = []
    private var selectionLoadTask: Task<Void, Never>?
    private var libraryRefreshTask: Task<Void, Never>?
    private var selectionGeneration: UInt64 = 0
    private var isRollingBackPointerSelection = false
    private var soundPackEditorWindowController: SoundPackEditorWindowController?

    var selectedSoundPack: SoundPackDescriptor {
        soundPacks.first { $0.id == settings.selectedProfileID }
            ?? SoundPackDescriptor.bundledDefaults.first { $0.id == SwitchProfile.holyPanda.rawValue }!
    }

    init(
        settings: AppSettings = AppSettings(),
        permission: InputMonitoringPermissionManager = InputMonitoringPermissionManager(),
        updates: UpdateController = UpdateController(),
        soundPackLibrary: SoundPackLibrary = SoundPackLibrary(),
        audioEngine: KeyboardAudioEngine = KeyboardAudioEngine(),
        keyboardMonitor: KeyboardMonitor = KeyboardMonitor(),
        startsServices: Bool = true
    ) {
        self.settings = settings
        self.permission = permission
        self.updates = updates
        self.soundPackLibrary = soundPackLibrary
        self.audioEngine = audioEngine
        self.keyboardMonitor = keyboardMonitor

        if let profile = SwitchProfile(rawValue: settings.selectedProfileID) {
            audioEngine.load(profile: profile)
        } else {
            audioEngine.load(profile: .holyPanda)
        }
        let initialPointerProfile = settings.selectedPointerProfile
        if !audioEngine.load(pointerProfile: initialPointerProfile) {
            let reason = audioEngine.pointerResourceError ?? "点击音资源不可用。"
            if initialPointerProfile != .classic,
               audioEngine.load(pointerProfile: .classic) {
                settings.selectedPointerProfile = .classic
                pointerSoundError = "\(initialPointerProfile.displayName) 载入失败，已回退到经典微动：\(reason)"
            } else {
                pointerSoundError = "\(initialPointerProfile.displayName) 载入失败：\(reason)"
            }
        }
        if startsServices {
            audioEngine.warmUp()
        }
        syncAudioError()
        settings.$selectedProfileID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] profileID in
                guard let self else { return }
                selectionGeneration &+= 1
                loadSoundPack(selectionID: profileID)
            }
            .store(in: &cancellables)
        settings.$selectedPointerProfileID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] profileID in
                guard let self else { return }
                if isRollingBackPointerSelection {
                    isRollingBackPointerSelection = false
                    return
                }
                loadPointerSoundProfile(profileID: profileID)
            }
            .store(in: &cancellables)

        guard startsServices else { return }
        refreshSoundPacks()
        startKeyboardMonitor()
        updates.scheduleAutomaticCheck()

        permission.$isGranted
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.startKeyboardMonitor() }
            .store(in: &cancellables)

        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in _ = self?.permission.refresh() }
            .store(in: &cancellables)
    }

    func requestInputMonitoring() {
        permission.request()
        startKeyboardMonitor()
    }

    func openInputMonitoringSettings() {
        permission.openSystemSettings()
    }

    func retryKeyboardMonitor() {
        _ = permission.refresh()
        startKeyboardMonitor()
    }

    func activateSoundPack(_ selectionID: String) {
        guard soundPacks.contains(where: { $0.id == selectionID }) else { return }
        if settings.selectedProfileID == selectionID {
            loadSoundPack(selectionID: selectionID)
        } else {
            settings.selectedProfileID = selectionID
        }
    }

    func refreshSoundPacks(selecting selectionID: String? = nil) {
        libraryRefreshTask?.cancel()
        let library = soundPackLibrary
        let selectionGenerationAtStart = selectionGeneration
        libraryRefreshTask = Task { [weak self] in
            do {
                let descriptors = try await library.descriptors()
                try Task.checkCancellation()
                guard let self else { return }
                soundPacks = descriptors
                soundPackError = nil

                let requestedID = if let selectionID,
                                     selectionGeneration == selectionGenerationAtStart {
                    selectionID
                } else {
                    settings.selectedProfileID
                }
                if descriptors.contains(where: { $0.id == requestedID }) {
                    if settings.selectedProfileID == requestedID {
                        loadSoundPack(selectionID: requestedID)
                    } else {
                        settings.selectedProfileID = requestedID
                    }
                } else {
                    settings.selectedProfileID = SwitchProfile.holyPanda.rawValue
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                soundPackError = "无法读取 DIY 音色库：\(error.localizedDescription)"
            }
        }
    }

    func reloadSelectedSoundPack() {
        refreshSoundPacks(selecting: settings.selectedProfileID)
    }

    func openSoundPackEditor() {
        let controller: SoundPackEditorWindowController
        if let existing = soundPackEditorWindowController {
            controller = existing
        } else {
            controller = SoundPackEditorWindowController(appModel: self)
            soundPackEditorWindowController = controller
        }
        controller.present()
    }

    func soundPackEditorWindowDidClose(_ controller: SoundPackEditorWindowController) {
        guard soundPackEditorWindowController === controller else { return }
        soundPackEditorWindowController = nil
    }

    func applicationShouldTerminate(
        _ application: NSApplication
    ) -> NSApplication.TerminateReply {
        soundPackEditorWindowController?.applicationShouldTerminate(application)
            ?? .terminateNow
    }

    func preview() {
        preview(keyCode: 0, phase: .press)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075) { [weak self] in
            guard let self else { return }
            self.preview(keyCode: 0, phase: .release)
        }
    }

    func preview(keyCode: UInt16, phase: KeySoundPhase) {
        audioEngine.play(
            keyCode: keyCode,
            phase: phase,
            volume: settings.volume,
            pitchVariation: settings.usesPitchVariation
        )
        syncAudioError()
    }

    func preview(audioAt url: URL) {
        audioEngine.preview(audioAt: url, volume: settings.volume)
        syncAudioError()
    }

    private func startKeyboardMonitor() {
        guard permission.isGranted else {
            keyboardMonitor.stop()
            monitoringState = .waitingForPermission
            return
        }
        let started = keyboardMonitor.start { [weak self] event in self?.handle(event) }
        monitoringState = started
            ? .running
            : .failed("无法启动全局键盘与点击监听。请退出并重新打开 SimuBoard 后再试。")
    }

    private func handle(_ event: GlobalInputEvent) {
        guard permission.isGranted else { return }
        switch event {
        case let .keyboard(keyboardEvent):
            handle(keyboardEvent)
        case let .pointer(pointerEvent):
            handle(pointerEvent)
        }
    }

    private func handle(_ event: KeyboardEvent) {
        guard settings.isEnabled else { return }
        if event.kind == .keyDown, event.isRepeat { return }
        if event.kind == .keyUp, !settings.playsReleaseSound { return }

        let phase: KeySoundPhase = event.kind == .keyDown ? .press : .release
        audioEngine.play(
            keyCode: event.keyCode,
            phase: phase,
            volume: settings.volume,
            pitchVariation: settings.usesPitchVariation
        )
        syncAudioError()
    }

    private func handle(_ event: PointerEvent) {
        guard settings.isPointerSoundEnabled else { return }
        if event.phase == .release, !settings.playsPointerReleaseSound { return }

        audioEngine.play(
            pointerButton: event.button,
            phase: event.phase,
            volume: settings.pointerVolume,
            pitchVariation: settings.usesPitchVariation
        )
        syncAudioError()
    }

    private func loadPointerSoundProfile(profileID: String) {
        guard let profile = PointerSoundProfile(rawValue: profileID) else {
            let fallback = audioEngine.loadedPointerProfile
            pointerSoundError = "无法识别所选点击音，继续使用 \(fallback.displayName)。"
            rollBackPointerSelection(to: fallback)
            return
        }
        guard audioEngine.load(pointerProfile: profile) else {
            let fallback = audioEngine.loadedPointerProfile
            let reason = audioEngine.pointerResourceError ?? "点击音资源不可用。"
            pointerSoundError = "\(profile.displayName) 载入失败，继续使用 \(fallback.displayName)：\(reason)"
            rollBackPointerSelection(to: fallback)
            syncAudioError()
            return
        }
        pointerSoundError = nil
        syncAudioError()
    }

    private func rollBackPointerSelection(to profile: PointerSoundProfile) {
        guard settings.selectedPointerProfileID != profile.rawValue else { return }
        isRollingBackPointerSelection = true
        settings.selectedPointerProfileID = profile.rawValue
    }

    private func loadSoundPack(selectionID: String) {
        selectionLoadTask?.cancel()
        if let profile = SwitchProfile(rawValue: selectionID) {
            audioEngine.load(profile: profile)
            soundPackError = nil
            syncAudioError()
            return
        }

        guard let packID = Self.customPackID(from: selectionID) else {
            audioEngine.load(profile: .holyPanda)
            soundPackError = "无法识别所选 DIY 音色。"
            syncAudioError()
            return
        }

        let library = soundPackLibrary
        selectionLoadTask = Task { [weak self] in
            do {
                let document = try await library.loadCustomPack(id: packID)
                try Task.checkCancellation()
                guard let self, settings.selectedProfileID == selectionID else { return }
                if audioEngine.load(document: document) {
                    soundPackError = nil
                } else {
                    let reason = audioEngine.lastError ?? "自定义音频资源不完整。"
                    let fallback = document.manifest.baseProfileID
                        .flatMap(SwitchProfile.init(rawValue:)) ?? .holyPanda
                    audioEngine.load(profile: fallback)
                    soundPackError = "DIY 音色载入失败，已回退到 \(fallback.displayName)：\(reason)"
                }
                syncAudioError()
            } catch is CancellationError {
                return
            } catch {
                guard let self, settings.selectedProfileID == selectionID else { return }
                soundPackError = "无法载入 DIY 音色：\(error.localizedDescription)"
                audioEngine.load(profile: .holyPanda)
                syncAudioError()
            }
        }
    }

    private static func customPackID(from selectionID: String) -> UUID? {
        let prefix = "custom:"
        guard selectionID.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(selectionID.dropFirst(prefix.count)))
    }

    private func syncAudioError() {
        let latest = audioEngine.engineError ?? audioEngine.resourceError
        if audioError != latest { audioError = latest }
    }

    isolated deinit {
        selectionLoadTask?.cancel()
        libraryRefreshTask?.cancel()
        keyboardMonitor.stop()
    }
}
