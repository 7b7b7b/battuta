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
    @MainActor
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
            try testOutputSnapshotRefreshGate(passed: &passed)
            try testRuntimeKeyboardOutputCompensationAndPoolDefaults(passed: &passed)
            try testKeyboardAndPointerRouteIntegration(passed: &passed)

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

    private static func testOutputSnapshotRefreshGate(passed: inout Int) throws {
        try check(
            KeyboardOutputSnapshotRefreshGate().minimumRefreshInterval == 0.25,
            "the default output snapshot cache should span normal typing intervals",
            passed: &passed
        )

        var gate = KeyboardOutputSnapshotRefreshGate(minimumRefreshInterval: 0.25)
        var readCount = 0

        let first = gate.resolveSnapshot(now: 10, readSnapshot: {
            readCount += 1
            return .init(isMuted: false, attenuationDB: -30)
        })
        try check(
            readCount == 1 && first == .init(isMuted: false, attenuationDB: -30),
            "the first refresh-gated output snapshot should always query Core Audio",
            passed: &passed
        )

        let cached = gate.resolveSnapshot(now: 10.01, readSnapshot: {
            readCount += 1
            return .init(isMuted: true, attenuationDB: nil)
        })
        try check(
            readCount == 1 && cached == first,
            "keystrokes inside the refresh window should reuse the cached output snapshot",
            passed: &passed
        )

        let refreshed = gate.resolveSnapshot(now: 10.26, readSnapshot: {
            readCount += 1
            return .init(isMuted: true, attenuationDB: nil)
        })
        try check(
            readCount == 2 && refreshed == .init(isMuted: true, attenuationDB: nil),
            "the cache should refresh once the throttle interval expires",
            passed: &passed
        )

        let forced = gate.resolveSnapshot(now: 10.261, forceRefresh: true, readSnapshot: {
            readCount += 1
            return .init(isMuted: false, attenuationDB: -12)
        })
        try check(
            readCount == 3 && forced == .init(isMuted: false, attenuationDB: -12),
            "forced refreshes should bypass the throttle interval",
            passed: &passed
        )

        gate.invalidate()
        let invalidated = gate.resolveSnapshot(now: 10.262, readSnapshot: {
            readCount += 1
            return .init(isMuted: false, attenuationDB: -9)
        })
        try check(
            readCount == 4 && invalidated == .init(isMuted: false, attenuationDB: -9),
            "invalidating the cache should force the next keystroke to re-read output volume",
            passed: &passed
        )
    }

    @MainActor
    private static func testRuntimeKeyboardOutputCompensationAndPoolDefaults(
        passed: inout Int
    ) throws {
        struct StubReader: SystemOutputVolumeReading {
            let snapshotValue: SystemOutputVolumeSnapshot

            func snapshot() -> SystemOutputVolumeSnapshot {
                snapshotValue
            }
        }

        let engine = KeyboardAudioEngine(
            voiceCount: 2,
            outputVolumeReader: StubReader(
                snapshotValue: .init(isMuted: false, attenuationDB: -37.75)
            )
        )
        engine.warmUp()

        let keyboardVoices = try reflectedProperty(
            named: "keyboardVoices",
            from: engine,
            as: [Any].self
        )
        try check(
            keyboardVoices.count == 2,
            "default keyboard pool size should follow the requested voice count",
            passed: &passed
        )

        let pointerVoices = try reflectedProperty(
            named: "pointerVoices",
            from: engine,
            as: [Any].self
        )
        try check(
            pointerVoices.count == 2,
            "default pointer pool size should inherit the requested voice count when no explicit override is provided",
            passed: &passed
        )

        let keyboardGainStages = try reflectedProperty(
            named: "keyboardGainStages",
            from: engine,
            as: [AVAudioUnitEQ].self
        )
        try check(
            keyboardGainStages.count == KeyboardAbsoluteVolumeCompensation.stageCount,
            "runtime graph should attach exactly five keyboard compensation stages",
            passed: &passed
        )
        let totalGain = keyboardGainStages.reduce(Float.zero) { partial, stage in
            partial + stage.globalGain
        }
        try check(
            abs(totalGain) < 0.001,
            "warmUp should keep compensation neutral until a measured sample peak is available",
            passed: &passed
        )

        let keyboardLimiter = try reflectedProperty(
            named: "keyboardLimiter",
            from: engine,
            as: AVAudioUnitEffect.self
        )
        try check(
            keyboardLimiter.audioComponentDescription.componentSubType
                == kAudioUnitSubType_PeakLimiter,
            "runtime keyboard bus should end in Apple's peak limiter",
            passed: &passed
        )
    }

    private static func testKeyboardAndPointerRouteIntegration(passed: inout Int) throws {
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
        try check(
            engineSource.contains("keyboardGainStages")
                && engineSource.contains("kAudioUnitSubType_PeakLimiter")
                && engineSource.contains("refreshKeyboardOutputCompensation(")
                && engineSource.contains("KeyboardOutputSnapshotRefreshGate"),
            "keyboard playback should define a gain-stage and limiter chain with a compensation refresh path",
            passed: &passed
        )
        try check(
            engineSource.contains("outputVolumeReader.snapshot()"),
            "keyboard compensation refresh should still route through a synchronous output snapshot reader",
            passed: &passed
        )

        guard let keyboardPlayStart = engineSource.range(
            of: "    func play(\n        keyCode: UInt16,"
        )?.lowerBound,
        let pointerPlayStart = engineSource.range(
            of: "    func play(\n        pointerButton: PointerButton,"
        )?.lowerBound else {
            throw AudioVariantHarnessFailure.assertion("could not isolate keyboard and pointer playback entrypoints")
        }
        let keyboardPlaySource = engineSource[keyboardPlayStart..<pointerPlayStart]
        try check(
            keyboardPlaySource.contains("playKeyboard("),
            "keyboard playback entrypoints should route through the compensated keyboard path",
            passed: &passed
        )

        guard let previewStart = engineSource.range(
            of: "    func preview(\n        audioAt url: URL,"
        )?.lowerBound,
        let builtInBufferStart = engineSource.range(
            of: "    private func makeBuiltInBuffers("
        )?.lowerBound else {
            throw AudioVariantHarnessFailure.assertion("could not isolate DIY preview playback")
        }
        let previewSource = engineSource[previewStart..<builtInBufferStart]
        try check(
            previewSource.contains("playKeyboard("),
            "DIY preview playback should reuse the compensated keyboard route",
            passed: &passed
        )

        guard let pointerBufferPlayStart = engineSource.range(
            of: "    private func playPointer("
        )?.lowerBound,
        let startEngineIfNeeded = engineSource.range(
            of: "    @discardableResult\n    private func startEngineIfNeeded()"
        )?.lowerBound else {
            throw AudioVariantHarnessFailure.assertion("could not isolate pointer playback helpers")
        }
        let pointerPlaybackSource = engineSource[pointerPlayStart..<previewStart]
        try check(
            pointerPlaybackSource.contains("playPointer("),
            "pointer playback should route through the direct pointer path",
            passed: &passed
        )
        try check(
            !pointerPlaybackSource.contains("refreshKeyboardOutputCompensation")
                && !pointerPlaybackSource.contains("keyboardGainStages"),
            "pointer playback should bypass keyboard compensation refresh and gain stages",
            passed: &passed
        )
        let pointerBufferSource = engineSource[pointerBufferPlayStart..<startEngineIfNeeded]
        try check(
            pointerBufferSource.contains("let voice = pointerVoices[pointerVoiceCursor]")
                && pointerBufferSource.contains("schedule("),
            "pointer helper playback should consume the pointer voice pool directly",
            passed: &passed
        )
        try check(
            engineSource.contains("options: [.interrupts]")
                && engineSource.contains("if !voice.player.isPlaying")
                && !engineSource.contains("voice.player.stop()"),
            "voice reuse should interrupt active buffers without a stop/play cycle on every keystroke",
            passed: &passed
        )

        guard let systemOutputRange = harnessScript.range(
            of: "SimuBoardMac/SimuBoardMac/Services/SystemOutputVolume.swift"
        ),
        let engineRange = harnessScript.range(
            of: "SimuBoardMac/SimuBoardMac/Services/KeyboardAudioEngine.swift"
        ) else {
            throw AudioVariantHarnessFailure.assertion("audio variant harness script should compile SystemOutputVolume.swift and KeyboardAudioEngine.swift")
        }
        try check(
            systemOutputRange.lowerBound < engineRange.lowerBound,
            "audio variant harness should compile SystemOutputVolume.swift before KeyboardAudioEngine.swift",
            passed: &passed
        )

        try check(
            projectSource.contains("SystemOutputVolume.swift in Sources")
                && projectSource.contains("SystemOutputVolume.swift */;")
                && projectSource.contains("path = SystemOutputVolume.swift;"),
            "SystemOutputVolume.swift should be wired into the Xcode project sources",
            passed: &passed
        )
    }

    private static func reflectedProperty<Value>(
        named name: String,
        from subject: some Any,
        as _: Value.Type
    ) throws -> Value {
        guard let value = Mirror(reflecting: subject).children.first(where: { $0.label == name })?.value as? Value else {
            throw AudioVariantHarnessFailure.assertion("missing reflected property \(name)")
        }
        return value
    }
}
