import AVFAudio
import Foundation

private enum AudioVariantHarnessFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case let .assertion(message): message
        }
    }
}

@main
private struct AudioVariantCoreHarness {
    static func main() {
        do {
            var passed = 0
            try check(
                KeyboardPlaybackVariantCycle.variants.count == 4,
                "keyboard samples should prepare exactly four playback variants",
                passed: &passed
            )
            try check(
                Set(KeyboardPlaybackVariantCycle.variants).count == 4,
                "all playback variants should have a distinct gain/rate recipe",
                passed: &passed
            )
            try check(
                KeyboardPlaybackVariantCycle.variants.contains(.original),
                "the original sound should remain one of the prepared variants",
                passed: &passed
            )
            try check(
                KeyboardPlaybackVariantCycle.variants.allSatisfy {
                    (0.9...1.1).contains($0.gain) && (0.95...1.05).contains($0.rate)
                },
                "pseudo-sample recipes should stay close to the source recording",
                passed: &passed
            )

            let order = KeyboardPlaybackVariantCycle.playbackOrder
            try check(
                order.allSatisfy(KeyboardPlaybackVariantCycle.variants.indices.contains),
                "the playback order should only reference prepared variants",
                passed: &passed
            )
            let counts = Dictionary(grouping: order, by: { $0 }).mapValues(\.count)
            try check(
                KeyboardPlaybackVariantCycle.variants.indices.allSatisfy {
                    counts[$0] == order.count / KeyboardPlaybackVariantCycle.variants.count
                },
                "the playback order should use every variant equally",
                passed: &passed
            )

            var cycle = KeyboardPlaybackVariantCycle()
            var prior: KeyboardPlaybackVariant?
            var observed = Set<KeyboardPlaybackVariant>()
            for _ in 0..<(order.count * 3) {
                let next = cycle.next(variationEnabled: true)
                try check(
                    next != prior,
                    "consecutive keystrokes should never reuse the same variant",
                    passed: &passed
                )
                observed.insert(next)
                prior = next
            }
            try check(
                observed == Set(KeyboardPlaybackVariantCycle.variants),
                "rotation should expose all four prepared variants",
                passed: &passed
            )

            var disabledCycle = KeyboardPlaybackVariantCycle()
            let first = disabledCycle.next(variationEnabled: true)
            let disabled = disabledCycle.next(variationEnabled: false)
            let resumed = disabledCycle.next(variationEnabled: true)
            try check(first == .original, "rotation should include the unmodified source", passed: &passed)
            try check(
                disabled == .original,
                "disabling variation should always preserve exact original playback",
                passed: &passed
            )
            try check(
                resumed == KeyboardPlaybackVariantCycle.variants[order[1]],
                "disabled playback should not consume the prepared rotation",
                passed: &passed
            )

            try testSharedVoiceSelection(passed: &passed)
            try testLiveVoiceVolume(passed: &passed)
            try testLeadingSilenceTrimming(passed: &passed)
            try testNormalOutputRouteIntegration(passed: &passed)

            print("Audio variant core harness passed: \(passed) assertions")
        } catch {
            fputs("Audio variant core harness FAILED: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func check(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        passed: inout Int
    ) throws {
        guard condition() else { throw AudioVariantHarnessFailure.assertion(message) }
        passed += 1
    }

    private static func testSharedVoiceSelection(passed: inout Int) throws {
        try check(
            AudioVoiceSelector.nextIndex(
                count: 0,
                cursor: 0,
                allowsStealing: true,
                isActive: { _ in false },
                lastScheduledEpoch: { _ in 0 }
            ) == nil,
            "an empty shared voice pool should reject playback",
            passed: &passed
        )

        let mixedActivity = [true, false, true, false]
        let mixedEpochs: [UInt64] = [1, 2, 3, 4]
        try check(
            AudioVoiceSelector.nextIndex(
                count: mixedActivity.count,
                cursor: 2,
                allowsStealing: true,
                isActive: { mixedActivity[$0] },
                lastScheduledEpoch: { mixedEpochs[$0] }
            ) == 3,
            "shared playback should prefer the next idle voice",
            passed: &passed
        )

        let allActive = [true, true, true, true]
        let scheduledEpochs: [UInt64] = [8, 3, 7, 6]
        try check(
            AudioVoiceSelector.nextIndex(
                count: allActive.count,
                cursor: 0,
                allowsStealing: false,
                isActive: { allActive[$0] },
                lastScheduledEpoch: { scheduledEpochs[$0] }
            ) == nil,
            "pointer playback should be dropped instead of interrupting a full keyboard pool",
            passed: &passed
        )
        try check(
            AudioVoiceSelector.nextIndex(
                count: allActive.count,
                cursor: 0,
                allowsStealing: true,
                isActive: { allActive[$0] },
                lastScheduledEpoch: { scheduledEpochs[$0] }
            ) == 1,
            "keyboard playback should steal the oldest voice only when every voice is active",
            passed: &passed
        )

        let tiedEpochs: [UInt64] = [3, 3, 5, 4]
        try check(
            AudioVoiceSelector.nextIndex(
                count: allActive.count,
                cursor: 2,
                allowsStealing: true,
                isActive: { allActive[$0] },
                lastScheduledEpoch: { tiedEpochs[$0] }
            ) == 0,
            "oldest-voice ties should resolve deterministically",
            passed: &passed
        )
    }

    private static func testLiveVoiceVolume(passed: inout Int) throws {
        let keyboardGain = AudioVoiceGainState(domain: .keyboard, sampleGain: 1.02)
        try check(
            abs(keyboardGain.outputVolume(masterGain: 0.5) - 0.51) < 0.000_001,
            "keyboard master gain should preserve the active sample's variation gain",
            passed: &passed
        )
        try check(
            keyboardGain.outputVolume(masterGain: 0.5, updating: .pointer) == nil,
            "a pointer-volume change should not alter an active keyboard voice",
            passed: &passed
        )
        try check(
            keyboardGain.outputVolume(masterGain: 2) == 1,
            "combined master and sample gain should clamp at unity",
            passed: &passed
        )

        let pointerGain = AudioVoiceGainState(domain: .pointer, sampleGain: 1)
        try check(
            pointerGain.outputVolume(masterGain: 0.24, updating: .pointer) == 0.24,
            "pointer-volume changes should update active pointer voices independently",
            passed: &passed
        )
        try check(
            pointerGain.outputVolume(masterGain: .nan) == 0,
            "non-finite live volume updates should fail silent",
            passed: &passed
        )

        let mixedActiveGains = [keyboardGain, pointerGain]
        let keyboardUpdates = mixedActiveGains.compactMap {
            $0.outputVolume(masterGain: 0.4, updating: .keyboard)
        }
        try check(
            keyboardUpdates.count == 1
                && abs(keyboardUpdates[0] - Float(0.4 * 1.02)) < 0.000_001,
            "a keyboard gain change should update only keyboard voices in a mixed active pool",
            passed: &passed
        )
        let pointerUpdates = mixedActiveGains.compactMap {
            $0.outputVolume(masterGain: 0.24, updating: .pointer)
        }
        try check(
            pointerUpdates == [0.24],
            "a pointer gain change should update only pointer voices in a mixed active pool",
            passed: &passed
        )
    }

    private static func testLeadingSilenceTrimming(passed: inout Int) throws {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: 48_000,
            channels: 1
        )!
        let frameCount: AVAudioFrameCount = 4_096
        let delayedOnset = 960
        let delayed = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        delayed.frameLength = frameCount
        delayed.floatChannelData![0].update(repeating: 0, count: Int(frameCount))
        delayed.floatChannelData![0][delayedOnset] = 0.5

        let trimmed = KeyboardLeadingSilenceTrimmer.trim(delayed)
        try check(
            trimmed.frameLength < delayed.frameLength,
            "excess source pre-roll should be removed while the pack is prepared",
            passed: &passed
        )
        let trimmedSamples = trimmed.floatChannelData![0]
        let firstAudibleFrame = (0..<Int(trimmed.frameLength)).first {
            abs(trimmedSamples[$0]) >= 0.0008
        }
        try check(
            firstAudibleFrame != nil && firstAudibleFrame! <= 16,
            "trimmed samples should retain only a tiny safety pre-roll",
            passed: &passed
        )
        try check(
            firstAudibleFrame.map { trimmedSamples[$0] == 0.5 } == true,
            "leading-silence trimming should preserve the original transient",
            passed: &passed
        )

        let immediate = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        immediate.frameLength = frameCount
        immediate.floatChannelData![0].update(repeating: 0, count: Int(frameCount))
        immediate.floatChannelData![0][4] = 0.5
        try check(
            KeyboardLeadingSilenceTrimmer.trim(immediate) === immediate,
            "already-aligned recordings should not be copied or shifted",
            passed: &passed
        )
    }

    private static func testNormalOutputRouteIntegration(passed: inout Int) throws {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let engineSource = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "SimuBoardMac/SimuBoardMac/Services/KeyboardAudioEngine.swift"
            ),
            encoding: .utf8
        )
        let harnessScript = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "SimuBoardMac/Tests/run-audio-variant-core-harness.sh"
            ),
            encoding: .utf8
        )
        let projectSource = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "SimuBoardMac/SimuBoardMac.xcodeproj/project.pbxproj"
            ),
            encoding: .utf8
        )
        let appModelSource = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "SimuBoardMac/SimuBoardMac/Services/AppModel.swift"
            ),
            encoding: .utf8
        )

        try check(
            engineSource.contains("private var voices: [Voice] = []")
                && !engineSource.contains("keyboardVoices")
                && !engineSource.contains("pointerVoices")
                && !engineSource.contains("keyboardVoiceCursor")
                && !engineSource.contains("pointerVoiceCursor")
                && !engineSource.contains("private enum VoicePool"),
            "keyboard and pointer playback should share one voice pool",
            passed: &passed
        )

        let removedCompensationSymbols = [
            "SystemOutputVolume",
            "KeyboardAbsoluteVolume",
            "keyboardGainStages",
            "keyboardLimiter",
            "outputVolumeReader",
            "refreshKeyboardOutputCompensation",
            "kAudioUnitSubType_PeakLimiter",
        ]
        try check(
            removedCompensationSymbols.allSatisfy { !engineSource.contains($0) },
            "keyboard playback should not retain system-volume readers, gain compensation, or a dedicated limiter",
            passed: &passed
        )
        try check(
            !harnessScript.contains("SystemOutputVolume.swift")
                && !projectSource.contains("SystemOutputVolume.swift"),
            "the removed system-volume reader should not remain in the harness or Xcode project",
            passed: &passed
        )
        try check(
            engineSource.contains("engine.isAutoShutdownEnabled = true")
                && !engineSource.contains("engine.isAutoShutdownEnabled = false"),
            "the audio engine should release idle hardware instead of continuously rendering silence",
            passed: &passed
        )
        try check(
            engineSource.contains("if startEngineIfNeeded() {\n            scheduleIdlePauseIfNeeded()\n        }"),
            "audio warm-up should schedule an idle pause even before the first sound plays",
            passed: &passed
        )

        guard let initializerStart = engineSource.range(
            of: "    init(voiceCount: Int = 16) {"
        )?.lowerBound,
        let initializerEnd = engineSource.range(
            of: "        engine.isAutoShutdownEnabled = true",
            range: initializerStart..<engineSource.endIndex
        )?.lowerBound else {
            throw AudioVariantHarnessFailure.assertion("could not isolate the audio-engine initializer")
        }
        let initializerSource = engineSource[initializerStart..<initializerEnd]
        try check(
            initializerSource.contains("voices = makeVoicePool(count: voiceCount")
                && initializerSource.components(separatedBy: "output: engine.mainMixerNode").count == 2,
            "one 16-voice shared pool should connect to the system-controlled main mixer",
            passed: &passed
        )

        guard let keyboardBufferPlayStart = engineSource.range(
            of: "    private func playKeyboard(\n        buffer: AVAudioPCMBuffer,"
        )?.lowerBound,
        let pointerBufferPlayStart = engineSource.range(
            of: "    private func playPointer(",
            range: keyboardBufferPlayStart..<engineSource.endIndex
        )?.lowerBound else {
            throw AudioVariantHarnessFailure.assertion("could not isolate keyboard playback")
        }
        let keyboardBufferSource = engineSource[keyboardBufferPlayStart..<pointerBufferPlayStart]
        try check(
            keyboardBufferSource.contains("nextVoiceIndex(allowsStealing: true)")
                && keyboardBufferSource.contains("schedule("),
            "keyboard playback should use the shared pool and may steal only when it is full",
            passed: &passed
        )

        guard let startEngineIfNeeded = engineSource.range(
            of: "    @discardableResult\n    private func startEngineIfNeeded()",
            range: pointerBufferPlayStart..<engineSource.endIndex
        )?.lowerBound else {
            throw AudioVariantHarnessFailure.assertion("could not isolate pointer playback helpers")
        }
        let pointerBufferSource = engineSource[pointerBufferPlayStart..<startEngineIfNeeded]
        try check(
            pointerBufferSource.contains("nextVoiceIndex(allowsStealing: false)")
                && pointerBufferSource.contains("schedule("),
            "pointer playback should use only idle shared voices without interrupting keyboard sound",
            passed: &passed
        )
        try check(
            engineSource.contains("AudioVoiceSelector.nextIndex(")
                && engineSource.contains("voice.lastScheduledEpoch = activityEpoch")
                && engineSource.contains("voices.allSatisfy { !$0.isActive }"),
            "the production path should prefer idle shared voices and track the oldest active voice",
            passed: &passed
        )
        try check(
            engineSource.contains("voice.gainState = gainState")
                && engineSource.contains("completionCallbackType: .dataPlayedBack")
                && engineSource.contains("if !voice.player.isPlaying"),
            "voice reuse should preserve the optimized interrupt path without a stop/play cycle",
            passed: &passed
        )
        try check(
            engineSource.contains("func setKeyboardPlaybackGain(_ gain: Double)")
                && engineSource.contains("func setPointerPlaybackGain(_ gain: Double)")
                && engineSource.contains("for voice in voices where voice.isActive")
                && engineSource.contains("updating: domain"),
            "live volume changes should update only matching active voices in the shared pool",
            passed: &passed
        )
        try check(
            appModelSource.contains("settings.$volume")
                && appModelSource.contains("KeyboardVolumeCurve.playbackGain(for: sliderPosition)")
                && appModelSource.contains("settings.$pointerVolume")
                && appModelSource.contains("setPointerPlaybackGain(gain)"),
            "settings publishers should push keyboard and pointer gain changes into active playback",
            passed: &passed
        )
        guard let scheduleStart = engineSource.range(
            of: "    private func schedule("
        )?.lowerBound,
        let nextVoiceStart = engineSource.range(
            of: "    private func nextVoiceIndex(",
            range: scheduleStart..<engineSource.endIndex
        )?.lowerBound else {
            throw AudioVariantHarnessFailure.assertion("could not isolate voice scheduling")
        }
        let scheduleSource = engineSource[scheduleStart..<nextVoiceStart]
        guard let configureGain = scheduleSource.range(
            of: "voice.player.volume = gainState.outputVolume"
        )?.lowerBound,
        let resumeEngine = scheduleSource.range(
            of: "guard startEngineIfNeeded()"
        )?.lowerBound else {
            throw AudioVariantHarnessFailure.assertion("could not verify idle-resume ordering")
        }
        try check(
            configureGain < resumeEngine,
            "an idle engine should receive the selected voice gain before it resumes rendering",
            passed: &passed
        )
        guard let advanceGeneration = scheduleSource.range(
            of: "voice.playbackGeneration &+= 1"
        )?.lowerBound,
        let replaceGainState = scheduleSource.range(
            of: "voice.gainState = gainState"
        )?.lowerBound else {
            throw AudioVariantHarnessFailure.assertion("could not verify stolen-voice state replacement")
        }
        try check(
            advanceGeneration < replaceGainState,
            "stealing a voice should advance its generation before installing the new domain and gain",
            passed: &passed
        )
        guard let finishStart = engineSource.range(
            of: "    private func finishPlayback("
        )?.lowerBound,
        let volumeUpdateStart = engineSource.range(
            of: "    private func updateActiveVoiceVolumes(",
            range: finishStart..<engineSource.endIndex
        )?.lowerBound else {
            throw AudioVariantHarnessFailure.assertion("could not isolate playback completion")
        }
        let finishSource = engineSource[finishStart..<volumeUpdateStart]
        guard let staleCompletionGuard = finishSource.range(
            of: "guard voice.playbackGeneration == generation else { return }"
        )?.lowerBound,
        let clearGainState = finishSource.range(
            of: "voice.gainState = nil"
        )?.lowerBound else {
            throw AudioVariantHarnessFailure.assertion("could not verify stale completion handling")
        }
        try check(
            staleCompletionGuard < clearGainState,
            "a stale completion must return before it can clear a stolen voice's new gain state",
            passed: &passed
        )
        try check(
            engineSource.contains("voice.playbackGeneration &+= 1")
                && engineSource.contains("guard voice.playbackGeneration == generation else { return }")
                && engineSource.contains("expectedActivityEpoch")
                && engineSource.contains("self.activityEpoch == expectedActivityEpoch")
                && engineSource.contains("try await Task.sleep(for: Self.idlePauseDelay)")
                && engineSource.contains("engine.pause()"),
            "completed voices should release the engine after a race-safe idle grace period",
            passed: &passed
        )
        try check(
            engineSource.contains("self.handleEngineConfigurationChange()")
                && engineSource.contains("if allVoicesAreIdle")
                && engineSource.contains("_ = startEngineIfNeeded()"),
            "audio-route changes should resume active playback without restarting an idle engine",
            passed: &passed
        )
    }
}
