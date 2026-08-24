import AVFAudio
import Foundation

struct KeyboardPlaybackVariant: Equatable, Hashable, Sendable {
    let gain: Float
    let rate: Float

    static let original = KeyboardPlaybackVariant(gain: 1, rate: 1)
}

struct KeyboardPlaybackVariantCycle: Sendable {
    static let variants: [KeyboardPlaybackVariant] = [
        .original,
        KeyboardPlaybackVariant(gain: 0.975, rate: 0.978),
        KeyboardPlaybackVariant(gain: 0.99, rate: 1.018),
        KeyboardPlaybackVariant(gain: 1.02, rate: 0.992),
    ]

    // Four balanced passes in different orders. The final entry also differs from
    // the first so wrapping the cycle cannot repeat the same variant.
    static let playbackOrder = [
        0, 2, 1, 3,
        1, 0, 3, 2,
        3, 1, 2, 0,
        2, 3, 0, 1,
    ]

    private(set) var cursor = 0

    mutating func next(variationEnabled: Bool) -> KeyboardPlaybackVariant {
        guard variationEnabled else { return .original }
        let variant = Self.variants[Self.playbackOrder[cursor]]
        cursor = (cursor + 1) % Self.playbackOrder.count
        return variant
    }
}

enum KeyboardLeadingSilenceTrimmer {
    private static let silenceThreshold: Float = 0.0008
    private static let maximumScanDuration = 0.25
    private static let preservedPrerollDuration = 0.00015
    private static let minimumTrimDuration = 0.0005

    static func trim(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard buffer.frameLength > 0,
              buffer.format.commonFormat == .pcmFormatFloat32,
              !buffer.format.isInterleaved,
              let sourceChannels = buffer.floatChannelData else { return buffer }

        let sampleRate = buffer.format.sampleRate
        let totalFrameCount = Int(buffer.frameLength)
        let scanFrameCount = min(
            totalFrameCount,
            Int(ceil(sampleRate * maximumScanDuration))
        )
        let channelCount = Int(buffer.format.channelCount)
        var firstAudibleFrame: Int?

        frameSearch: for frame in 0..<scanFrameCount {
            for channel in 0..<channelCount
            where abs(sourceChannels[channel][frame]) >= silenceThreshold {
                firstAudibleFrame = frame
                break frameSearch
            }
        }

        guard let firstAudibleFrame else { return buffer }
        let prerollFrameCount = Int(ceil(sampleRate * preservedPrerollDuration))
        let trimFrameCount = max(0, firstAudibleFrame - prerollFrameCount)
        let minimumTrimFrameCount = Int(ceil(sampleRate * minimumTrimDuration))
        guard trimFrameCount >= minimumTrimFrameCount,
              trimFrameCount < totalFrameCount else { return buffer }

        let remainingFrameCount = totalFrameCount - trimFrameCount
        guard let trimmed = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: AVAudioFrameCount(remainingFrameCount)
        ), let destinationChannels = trimmed.floatChannelData else { return buffer }

        for channel in 0..<channelCount {
            destinationChannels[channel].update(
                from: sourceChannels[channel].advanced(by: trimFrameCount),
                count: remainingFrameCount
            )
        }
        trimmed.frameLength = AVAudioFrameCount(remainingFrameCount)
        return trimmed
    }
}

@MainActor
final class KeyboardAudioEngine {
    private static let playbackSampleRate = 48_000.0
    private static let conversionCapacityPadding: AVAudioFrameCount = 32

    private struct BufferKey: Hashable {
        let phase: KeySoundPhase
        let sample: KeySoundSample
    }

    private struct PointerBufferKey: Hashable {
        let phase: PointerSoundPhase
        let sample: PointerSoundSample
    }

    private enum ResourceDomain {
        case keyboard
        case pointer
    }

    private struct Voice {
        let player: AVAudioPlayerNode
        let speed: AVAudioUnitVarispeed
    }

    private final class PreparedKeyboardSample {
        let buffer: AVAudioPCMBuffer
        private var variants = KeyboardPlaybackVariantCycle()

        init(buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }

        func nextVariant(variationEnabled: Bool) -> KeyboardPlaybackVariant {
            variants.next(variationEnabled: variationEnabled)
        }
    }

    private let engine = AVAudioEngine()
    private let playbackFormat = AVAudioFormat(
        standardFormatWithSampleRate: playbackSampleRate,
        channels: 1
    )!
    private let keyboardMixer: AVAudioMixerNode
    private let keyboardGainStages: [AVAudioUnitEQ]
    private let outputVolumeReader: any SystemOutputVolumeReading
    private var keyboardVoices: [Voice] = []
    private var pointerVoices: [Voice] = []
    private var buffers: [BufferKey: PreparedKeyboardSample] = [:]
    private var pointerBuffers: [PointerBufferKey: AVAudioPCMBuffer] = [:]
    private var customBuffers: [SoundPackAssetID: PreparedKeyboardSample] = [:]
    private var customResolver: SoundPackResolver?
    private var keyboardVoiceCursor = 0
    private var pointerVoiceCursor = 0
    private var keyboardOutputCompensationPlan = KeyboardAbsoluteVolumeCompensation.plan(
        for: .init(isMuted: false, attenuationDB: nil)
    )
    private var configurationObserver: NSObjectProtocol?
    private(set) var loadedProfile: SwitchProfile = .holyPanda
    private(set) var loadedSelectionID: String = SwitchProfile.holyPanda.rawValue
    private(set) var loadedPointerProfile: PointerSoundProfile = .classic
    private(set) var engineError: String?
    private(set) var resourceError: String?
    private(set) var pointerResourceError: String?

    var lastError: String? { engineError ?? resourceError ?? pointerResourceError }

    init(
        voiceCount: Int = 16,
        pointerVoiceCount: Int? = nil,
        outputVolumeReader: any SystemOutputVolumeReading = CoreAudioSystemOutputVolumeReader()
    ) {
        self.keyboardMixer = AVAudioMixerNode()
        self.keyboardGainStages = (0..<KeyboardAbsoluteVolumeCompensation.stageCount).map { _ in
            let stage = AVAudioUnitEQ(numberOfBands: 0)
            stage.globalGain = 0
            return stage
        }
        self.outputVolumeReader = outputVolumeReader

        engine.attach(keyboardMixer)
        for stage in keyboardGainStages {
            engine.attach(stage)
        }
        connectKeyboardOutputChain()
        keyboardVoices = makeVoicePool(count: voiceCount, output: keyboardMixer)
        pointerVoices = makeVoicePool(
            count: pointerVoiceCount ?? voiceCount,
            output: engine.mainMixerNode
        )
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
                self.refreshKeyboardOutputCompensation(forceApply: true)
                _ = self.startEngineIfNeeded()
            }
        }
    }

    func warmUp() {
        refreshKeyboardOutputCompensation(forceApply: true)
        engine.prepare()
        _ = startEngineIfNeeded()
    }

    @discardableResult
    func load(profile: SwitchProfile) -> Bool {
        resourceError = nil
        guard let nextBuffers = makeBuiltInBuffers(profile: profile) else { return false }
        loadedProfile = profile
        loadedSelectionID = profile.rawValue
        buffers = nextBuffers
        customBuffers = [:]
        customResolver = nil
        return true
    }

    @discardableResult
    func load(document: SoundPackDocument) -> Bool {
        resourceError = nil
        let baseProfile = document.manifest.baseProfileID
            .flatMap(SwitchProfile.init(rawValue:)) ?? .holyPanda
        guard let nextBuiltInBuffers = makeBuiltInBuffers(profile: baseProfile) else { return false }

        var nextCustomBuffers: [SoundPackAssetID: PreparedKeyboardSample] = [:]
        for assetID in document.manifest.referencedAssetIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            do {
                let url = try document.assetURL(for: assetID)
                guard let buffer = loadBuffer(at: url) else {
                    if resourceError == nil {
                        resourceError = "无法预载自定义音频 \(url.lastPathComponent)。"
                    }
                    return false
                }
                nextCustomBuffers[assetID] = prepareKeyboardSample(buffer)
            } catch {
                resourceError = "无法读取自定义音频：\(error.localizedDescription)"
                return false
            }
        }

        loadedProfile = baseProfile
        loadedSelectionID = document.id
        buffers = nextBuiltInBuffers
        customBuffers = nextCustomBuffers
        customResolver = SoundPackResolver(manifest: document.manifest)
        return true
    }

    @discardableResult
    func load(pointerProfile: PointerSoundProfile) -> Bool {
        pointerResourceError = nil
        guard let nextBuffers = makePointerBuffers(profile: pointerProfile) else {
            return false
        }
        loadedPointerProfile = pointerProfile
        pointerBuffers = nextBuffers
        return true
    }

    func play(
        keyCode: UInt16,
        phase: KeySoundPhase,
        volume: Double,
        pitchVariation: Bool
    ) {
        if let customResolver {
            switch customResolver.resolution(for: keyCode, phase: phase) {
            case let .asset(assetID, _):
                guard let sample = customBuffers[assetID] else { return }
                playKeyboard(sample: sample, volume: volume, pitchVariation: pitchVariation)
                return
            case .silent:
                return
            case .missing:
                break
            }
        }

        guard let sample = KeySoundMapper.sample(
            for: keyCode,
            phase: phase,
            profile: loadedProfile
        ) else { return }
        playKeyboard(
            sample: sample,
            phase: phase,
            volume: volume,
            pitchVariation: pitchVariation
        )
    }

    func play(
        pointerButton: PointerButton,
        phase: PointerSoundPhase,
        volume: Double,
        pitchVariation: Bool
    ) {
        let requestedKey = PointerBufferKey(phase: phase, sample: pointerButton.sample)
        let fallbackKey = PointerBufferKey(phase: phase, sample: .primary)
        guard let buffer = pointerBuffers[requestedKey] ?? pointerBuffers[fallbackKey] else {
            return
        }
        playPointer(
            buffer: buffer,
            volume: volume,
            pitchVariation: pitchVariation,
            baseRate: pointerButton.playbackRate
        )
    }

    func preview(
        audioAt url: URL,
        volume: Double,
        pitchVariation: Bool = false
    ) {
        resourceError = nil
        guard let buffer = loadBuffer(at: url) else {
            if resourceError == nil {
                resourceError = "无法读取 \(url.lastPathComponent)。"
            }
            return
        }
        playKeyboard(buffer: buffer, volume: volume, pitchVariation: pitchVariation)
    }

    private func makeBuiltInBuffers(profile: SwitchProfile) -> [BufferKey: PreparedKeyboardSample]? {
        var nextBuffers: [BufferKey: PreparedKeyboardSample] = [:]

        let genericPressSamples: [KeySoundSample] = [
            .genericR0, .genericR1, .genericR2, .genericR3, .genericR4
        ]
        let pressSamples = profile.hasDedicatedSpecialKeySamples
            ? genericPressSamples + [.space, .enter, .backspace]
            : genericPressSamples
        let releaseSamples: [KeySoundSample] = if !profile.supportsReleaseSound {
            []
        } else if profile.hasRowSpecificReleaseSamples {
            profile.hasDedicatedSpecialKeySamples
                ? genericPressSamples + [.space, .enter, .backspace]
                : genericPressSamples
        } else if profile.hasDedicatedSpecialKeySamples {
            [.generic, .space, .enter, .backspace]
        } else {
            [.generic]
        }

        for sample in pressSamples {
            if let buffer = loadBuffer(profile: profile, phase: .press, sample: sample) {
                nextBuffers[BufferKey(phase: .press, sample: sample)] = prepareKeyboardSample(buffer)
            }
        }
        for sample in releaseSamples {
            if let buffer = loadBuffer(profile: profile, phase: .release, sample: sample) {
                nextBuffers[BufferKey(phase: .release, sample: sample)] = prepareKeyboardSample(buffer)
            }
        }

        let expectedBufferCount = pressSamples.count + releaseSamples.count
        guard nextBuffers.count == expectedBufferCount else {
            if resourceError == nil {
                resourceError = "\(profile.displayName) 的音频资源不完整（\(nextBuffers.count)/\(expectedBufferCount)）。"
            }
            return nil
        }
        return nextBuffers
    }

    private func prepareKeyboardSample(_ buffer: AVAudioPCMBuffer) -> PreparedKeyboardSample {
        // Every recipe shares this one onset-aligned PCM buffer. Variants never add
        // a start offset, and large DIY packs therefore do not incur 4x PCM memory.
        PreparedKeyboardSample(buffer: KeyboardLeadingSilenceTrimmer.trim(buffer))
    }

    private func makePointerBuffers(
        profile: PointerSoundProfile
    ) -> [PointerBufferKey: AVAudioPCMBuffer]? {
        var nextBuffers: [PointerBufferKey: AVAudioPCMBuffer] = [:]
        for phase in PointerSoundPhase.allCases {
            let key = PointerBufferKey(phase: phase, sample: .primary)
            if let buffer = loadPointerBuffer(
                profile: profile,
                phase: phase,
                sample: .primary
            ) {
                nextBuffers[key] = buffer
            }
        }

        guard nextBuffers.count == PointerSoundPhase.allCases.count else {
            if pointerResourceError == nil {
                pointerResourceError = "\(profile.displayName) 的点击音资源不完整（\(nextBuffers.count)/\(PointerSoundPhase.allCases.count)）。"
            }
            return nil
        }
        return nextBuffers
    }

    private func playKeyboard(
        sample: KeySoundSample,
        phase: KeySoundPhase,
        volume: Double,
        pitchVariation: Bool
    ) {
        let fallback: KeySoundSample = if phase == .release {
            loadedProfile.hasRowSpecificReleaseSamples ? .genericR2 : .generic
        } else {
            .genericR2
        }
        guard let preparedSample = buffers[BufferKey(phase: phase, sample: sample)]
            ?? buffers[BufferKey(phase: phase, sample: fallback)] else { return }

        playKeyboard(sample: preparedSample, volume: volume, pitchVariation: pitchVariation)
    }

    private func playKeyboard(
        sample: PreparedKeyboardSample,
        volume: Double,
        pitchVariation: Bool
    ) {
        let variant = sample.nextVariant(variationEnabled: pitchVariation)
        playKeyboard(
            buffer: sample.buffer,
            volume: volume * Double(variant.gain),
            pitchVariation: false,
            baseRate: variant.rate
        )
    }

    private func playKeyboard(
        buffer: AVAudioPCMBuffer,
        volume: Double,
        pitchVariation: Bool,
        baseRate: Float = 1
    ) {
        let plan = refreshKeyboardOutputCompensation()
        guard plan.shouldPlay else { return }
        guard startEngineIfNeeded() else { return }
        guard !keyboardVoices.isEmpty else { return }

        let voice = keyboardVoices[keyboardVoiceCursor]
        keyboardVoiceCursor = (keyboardVoiceCursor + 1) % keyboardVoices.count
        voice.player.stop()
        voice.player.volume = Float(max(0, min(1, volume)))
        let variation: Float = pitchVariation ? .random(in: 0.97...1.03) : 1
        voice.speed.rate = max(0.25, min(4, baseRate * variation))
        voice.player.scheduleBuffer(buffer, at: nil, options: [])
        voice.player.play()
    }

    private func playPointer(
        buffer: AVAudioPCMBuffer,
        volume: Double,
        pitchVariation: Bool,
        baseRate: Float = 1
    ) {
        guard startEngineIfNeeded() else { return }
        guard !pointerVoices.isEmpty else { return }

        let voice = pointerVoices[pointerVoiceCursor]
        pointerVoiceCursor = (pointerVoiceCursor + 1) % pointerVoices.count
        voice.player.stop()
        voice.player.volume = Float(max(0, min(1, volume)))
        let variation: Float = pitchVariation ? .random(in: 0.97...1.03) : 1
        voice.speed.rate = max(0.25, min(4, baseRate * variation))
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

    private func connectKeyboardOutputChain() {
        guard let firstStage = keyboardGainStages.first,
              let lastStage = keyboardGainStages.last else {
            engine.connect(keyboardMixer, to: engine.mainMixerNode, format: playbackFormat)
            return
        }

        engine.connect(keyboardMixer, to: firstStage, format: playbackFormat)
        for (upstream, downstream) in zip(keyboardGainStages, keyboardGainStages.dropFirst()) {
            engine.connect(upstream, to: downstream, format: playbackFormat)
        }
        engine.connect(lastStage, to: engine.mainMixerNode, format: playbackFormat)
    }

    private func makeVoicePool(count: Int, output: AVAudioNode) -> [Voice] {
        var voices = [Voice]()
        voices.reserveCapacity(count)

        for _ in 0..<count {
            let player = AVAudioPlayerNode()
            let speed = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(speed)
            engine.connect(player, to: speed, format: playbackFormat)
            engine.connect(speed, to: output, format: playbackFormat)
            voices.append(Voice(player: player, speed: speed))
        }

        return voices
    }

    @discardableResult
    private func refreshKeyboardOutputCompensation(
        forceApply: Bool = false
    ) -> KeyboardAbsoluteVolumePlan {
        let nextPlan = KeyboardAbsoluteVolumeCompensation.plan(for: outputVolumeReader.snapshot())
        let didChange = nextPlan != keyboardOutputCompensationPlan
        if didChange {
            stopKeyboardVoices()
        }
        if didChange || forceApply {
            applyKeyboardOutputCompensation(nextPlan)
            keyboardOutputCompensationPlan = nextPlan
        }
        return nextPlan
    }

    private func stopKeyboardVoices() {
        for voice in keyboardVoices {
            voice.player.stop()
        }
    }

    private func applyKeyboardOutputCompensation(_ plan: KeyboardAbsoluteVolumePlan) {
        for (stage, gain) in zip(keyboardGainStages, plan.stageGainsDB) {
            stage.globalGain = gain
        }
        if plan.stageGainsDB.count < keyboardGainStages.count {
            for stage in keyboardGainStages.dropFirst(plan.stageGainsDB.count) {
                stage.globalGain = 0
            }
        }
    }

    private func loadBuffer(
        profile: SwitchProfile,
        phase: KeySoundPhase,
        sample: KeySoundSample
    ) -> AVAudioPCMBuffer? {
        let directory = "Audio/\(profile.rawValue)/\(phase.rawValue)"
        let supportedExtensions = ["wav", "mp3"]
        guard let url = supportedExtensions.lazy.compactMap({ fileExtension in
            Bundle.main.url(
                forResource: sample.rawValue,
                withExtension: fileExtension,
                subdirectory: directory
            )
        }).first else { return nil }

        return loadBuffer(at: url)
    }

    private func loadPointerBuffer(
        profile: PointerSoundProfile,
        phase: PointerSoundPhase,
        sample: PointerSoundSample
    ) -> AVAudioPCMBuffer? {
        let directory = "Audio/pointer/\(profile.rawValue)/\(phase.rawValue)"
        let supportedExtensions = ["wav", "mp3"]
        guard let url = supportedExtensions.lazy.compactMap({ fileExtension in
            Bundle.main.url(
                forResource: sample.rawValue,
                withExtension: fileExtension,
                subdirectory: directory
            )
        }).first else { return nil }

        return loadBuffer(at: url, resourceDomain: .pointer)
    }

    private func loadBuffer(
        at url: URL,
        resourceDomain: ResourceDomain = .keyboard
    ) -> AVAudioPCMBuffer? {
        let didStartSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else { return nil }
            try file.read(into: buffer)
            guard let convertedBuffer = convertToPlaybackFormat(buffer) else {
                setResourceError(
                    "无法将 \(url.lastPathComponent) 预转换为 48 kHz。",
                    domain: resourceDomain
                )
                return nil
            }
            return convertedBuffer
        } catch {
            setResourceError(
                "无法预载 \(url.lastPathComponent)：\(error.localizedDescription)",
                domain: resourceDomain
            )
            return nil
        }
    }

    private func setResourceError(_ message: String, domain: ResourceDomain) {
        switch domain {
        case .keyboard:
            resourceError = message
        case .pointer:
            pointerResourceError = message
        }
    }

    private func convertToPlaybackFormat(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard source.frameLength > 0 else { return nil }
        if source.format == playbackFormat { return source }
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
