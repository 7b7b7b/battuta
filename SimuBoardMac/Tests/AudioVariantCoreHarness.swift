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

        try check(
            engineSource.contains("private var keyboardVoices: [Voice] = []")
                && engineSource.contains("private var pointerVoices: [Voice] = []"),
            "keyboard and pointer playback should maintain distinct voice pools",
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

        guard let initializerStart = engineSource.range(
            of: "    init(\n        voiceCount: Int = 16,"
        )?.lowerBound,
        let initializerEnd = engineSource.range(
            of: "        engine.isAutoShutdownEnabled = false",
            range: initializerStart..<engineSource.endIndex
        )?.lowerBound else {
            throw AudioVariantHarnessFailure.assertion("could not isolate the audio-engine initializer")
        }
        let initializerSource = engineSource[initializerStart..<initializerEnd]
        try check(
            initializerSource.contains("keyboardVoices = makeVoicePool(")
                && initializerSource.contains("pointerVoices = makeVoicePool(")
                && initializerSource.components(separatedBy: "output: engine.mainMixerNode").count == 3,
            "both voice pools should connect directly to the system-controlled main mixer",
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
            keyboardBufferSource.contains("let voice = keyboardVoices[keyboardVoiceCursor]")
                && keyboardBufferSource.contains("schedule("),
            "keyboard playback should apply only the in-app gain before normal system output",
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
            pointerBufferSource.contains("let voice = pointerVoices[pointerVoiceCursor]")
                && pointerBufferSource.contains("schedule("),
            "pointer playback should keep its independent pool and normal system-relative gain",
            passed: &passed
        )
        try check(
            engineSource.contains("voice.player.volume = volume")
                && engineSource.contains("voice.player.scheduleBuffer(buffer, at: nil, options: [.interrupts])")
                && engineSource.contains("if !voice.player.isPlaying")
                && !engineSource.contains("voice.player.stop()"),
            "voice reuse should preserve the optimized interrupt path without a stop/play cycle",
            passed: &passed
        )
    }
}
