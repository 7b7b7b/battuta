import AVFAudio
import Foundation

@MainActor
final class KeyboardAudioEngine {
    private struct BufferKey: Hashable {
        let phase: KeySoundPhase
        let sample: KeySoundSample
    }

    private struct Voice {
        let player: AVAudioPlayerNode
        let speed: AVAudioUnitVarispeed
    }

    private let engine = AVAudioEngine()
    private let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var voices: [Voice] = []
    private var buffers: [BufferKey: AVAudioPCMBuffer] = [:]
    private var voiceCursor = 0
    private var configurationObserver: NSObjectProtocol?
    private(set) var loadedProfile: SwitchProfile = .holyPanda
    private(set) var engineError: String?
    private(set) var resourceError: String?

    var lastError: String? { engineError ?? resourceError }

    init(voiceCount: Int = 16) {
        for _ in 0..<voiceCount {
            let player = AVAudioPlayerNode()
            let speed = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(speed)
            engine.connect(player, to: speed, format: sourceFormat)
            engine.connect(speed, to: engine.mainMixerNode, format: sourceFormat)
            voices.append(Voice(player: player, speed: speed))
        }
        engine.prepare()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.engine.prepare()
                _ = self.startEngineIfNeeded()
            }
        }
    }

    func load(profile: SwitchProfile) {
        var nextBuffers: [BufferKey: AVAudioPCMBuffer] = [:]
        resourceError = nil

        let pressSamples: [KeySoundSample] = profile.usesOnlyGenericSamples
            ? [.genericR0, .genericR1, .genericR2, .genericR3, .genericR4]
            : [.genericR0, .genericR1, .genericR2, .genericR3, .genericR4, .space, .enter, .backspace]
        let releaseSamples: [KeySoundSample] = profile.usesOnlyGenericSamples
            ? [.generic]
            : [.generic, .space, .enter, .backspace]

        for sample in pressSamples {
            if let buffer = loadBuffer(profile: profile, phase: .press, sample: sample) {
                nextBuffers[BufferKey(phase: .press, sample: sample)] = buffer
            }
        }
        for sample in releaseSamples {
            if let buffer = loadBuffer(profile: profile, phase: .release, sample: sample) {
                nextBuffers[BufferKey(phase: .release, sample: sample)] = buffer
            }
        }

        guard !nextBuffers.isEmpty else {
            resourceError = "没有找到 \(profile.displayName) 的音频资源。"
            return
        }
        loadedProfile = profile
        buffers = nextBuffers
    }

    func play(
        sample: KeySoundSample,
        phase: KeySoundPhase,
        volume: Double,
        pitchVariation: Bool
    ) {
        guard startEngineIfNeeded() else { return }
        guard !voices.isEmpty else { return }

        let fallback: KeySoundSample = phase == .release ? .generic : .genericR2
        guard let buffer = buffers[BufferKey(phase: phase, sample: sample)]
            ?? buffers[BufferKey(phase: phase, sample: fallback)] else { return }

        let voice = voices[voiceCursor]
        voiceCursor = (voiceCursor + 1) % voices.count
        voice.player.stop()
        voice.player.volume = Float(max(0, min(1, volume)))
        voice.speed.rate = pitchVariation ? Float.random(in: 0.97...1.03) : 1
        voice.player.scheduleBuffer(buffer, at: nil, options: [])
        voice.player.play()
    }

    @discardableResult
    private func startEngineIfNeeded() -> Bool {
        guard !engine.isRunning else { return true }
        do {
            try engine.start()
            engineError = nil
            return true
        } catch {
            engineError = "音频引擎启动失败：\(error.localizedDescription)"
            return false
        }
    }

    private func loadBuffer(
        profile: SwitchProfile,
        phase: KeySoundPhase,
        sample: KeySoundSample
    ) -> AVAudioPCMBuffer? {
        let directory = "Audio/\(profile.rawValue)/\(phase.rawValue)"
        guard let url = Bundle.main.url(
            forResource: sample.rawValue,
            withExtension: "mp3",
            subdirectory: directory
        ) else { return nil }

        do {
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else { return nil }
            try file.read(into: buffer)
            return buffer
        } catch {
            resourceError = "无法读取 \(url.lastPathComponent)：\(error.localizedDescription)"
            return nil
        }
    }

    isolated deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }
}
