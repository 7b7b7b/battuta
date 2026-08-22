import AVFAudio
import Foundation

@MainActor
final class KeyboardAudioEngine {
    private static let playbackSampleRate = 48_000.0
    private static let conversionCapacityPadding: AVAudioFrameCount = 32

    private struct BufferKey: Hashable {
        let phase: KeySoundPhase
        let sample: KeySoundSample
    }

    private struct Voice {
        let player: AVAudioPlayerNode
        let speed: AVAudioUnitVarispeed
    }

    private let engine = AVAudioEngine()
    private let playbackFormat = AVAudioFormat(
        standardFormatWithSampleRate: playbackSampleRate,
        channels: 1
    )!
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
            engine.connect(player, to: speed, format: playbackFormat)
            engine.connect(speed, to: engine.mainMixerNode, format: playbackFormat)
            voices.append(Voice(player: player, speed: speed))
        }
        engine.isAutoShutdownEnabled = false
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

    func warmUp() {
        engine.prepare()
        _ = startEngineIfNeeded()
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
            guard let convertedBuffer = convertToPlaybackFormat(buffer) else {
                resourceError = "无法将 \(url.lastPathComponent) 预转换为 48 kHz。"
                return nil
            }
            return convertedBuffer
        } catch {
            resourceError = "无法预载 \(url.lastPathComponent)：\(error.localizedDescription)"
            return nil
        }
    }

    private func convertToPlaybackFormat(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard source.frameLength > 0 else { return nil }
        guard let converter = AVAudioConverter(from: source.format, to: playbackFormat) else {
            return nil
        }

        let ratio = playbackFormat.sampleRate / source.format.sampleRate
        let estimatedFrameCount = ceil(Double(source.frameLength) * ratio)
        let maximumFrameCount = Double(
            AVAudioFrameCount.max - Self.conversionCapacityPadding
        )
        guard estimatedFrameCount.isFinite,
              estimatedFrameCount > 0,
              estimatedFrameCount <= maximumFrameCount else { return nil }

        let capacity = AVAudioFrameCount(estimatedFrameCount)
            + Self.conversionCapacityPadding
        guard let output = AVAudioPCMBuffer(
            pcmFormat: playbackFormat,
            frameCapacity: capacity
        ) else { return nil }

        var didProvideInput = false
        var didReachEnd = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            guard !didProvideInput else {
                didReachEnd = true
                inputStatus.pointee = .endOfStream
                return nil
            }
            didProvideInput = true
            inputStatus.pointee = .haveData
            return source
        }

        guard conversionError == nil,
              didReachEnd,
              output.frameLength > 0 else { return nil }
        switch status {
        case .haveData, .endOfStream:
            return output
        case .error, .inputRanDry:
            return nil
        @unknown default:
            return nil
        }
    }

    isolated deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }
}
