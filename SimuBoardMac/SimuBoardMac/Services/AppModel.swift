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
    @Published private(set) var monitoringState: KeyboardMonitoringState = .stopped
    @Published private(set) var audioError: String?

    private let audioEngine: KeyboardAudioEngine
    private let keyboardMonitor: KeyboardMonitor
    private var cancellables: Set<AnyCancellable> = []

    init(
        settings: AppSettings = AppSettings(),
        permission: InputMonitoringPermissionManager = InputMonitoringPermissionManager(),
        audioEngine: KeyboardAudioEngine = KeyboardAudioEngine(),
        keyboardMonitor: KeyboardMonitor = KeyboardMonitor(),
        startsServices: Bool = true
    ) {
        self.settings = settings
        self.permission = permission
        self.audioEngine = audioEngine
        self.keyboardMonitor = keyboardMonitor

        audioEngine.load(profile: settings.selectedProfile)
        if startsServices {
            audioEngine.warmUp()
        }
        syncAudioError()
        guard startsServices else { return }
        startKeyboardMonitor()

        settings.$selectedProfileID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] profileID in
                guard let profile = SwitchProfile(rawValue: profileID) else { return }
                self?.audioEngine.load(profile: profile)
                self?.syncAudioError()
            }
            .store(in: &cancellables)

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

    func preview() {
        let profile = settings.selectedProfile
        if audioEngine.loadedProfile != profile { audioEngine.load(profile: profile) }
        audioEngine.play(
            sample: .genericR2,
            phase: .press,
            volume: settings.volume,
            pitchVariation: settings.usesPitchVariation
        )
        syncAudioError()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075) { [weak self] in
            guard let self else { return }
            self.audioEngine.play(
                sample: .generic,
                phase: .release,
                volume: self.settings.volume,
                pitchVariation: self.settings.usesPitchVariation
            )
            self.syncAudioError()
        }
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
            : .failed("无法启动全局键盘监听。请退出并重新打开 SimuBoard 后再试。")
    }

    private func handle(_ event: KeyboardEvent) {
        guard settings.isEnabled, permission.isGranted else { return }
        if event.kind == .keyDown, event.isRepeat { return }
        if event.kind == .keyUp, !settings.playsReleaseSound { return }

        let phase: KeySoundPhase = event.kind == .keyDown ? .press : .release
        guard let sample = KeySoundMapper.sample(
            for: event.keyCode,
            phase: phase,
            profile: settings.selectedProfile
        ) else { return }

        audioEngine.play(
            sample: sample,
            phase: phase,
            volume: settings.volume,
            pitchVariation: settings.usesPitchVariation
        )
        syncAudioError()
    }

    private func syncAudioError() {
        let latest = audioEngine.lastError
        if audioError != latest { audioError = latest }
    }

    isolated deinit {
        keyboardMonitor.stop()
    }
}
