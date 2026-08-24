import Foundation

private enum AbsoluteVolumeHarnessFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case let .assertion(message):
            message
        }
    }
}

@main
private struct AbsoluteVolumeCoreHarness {
    static func main() {
        do {
            var passed = 0

            let stereoObserved = SystemOutputVolumeResolver.snapshot(
                muteValue: false,
                channels: [
                    .init(scalar: 0.62, decibels: -38),
                    .init(scalar: 0.62, decibels: -38)
                ],
                hasSoftwareVolume: true
            )
            try check(
                !stereoObserved.isMuted
                    && stereoObserved.attenuationDB.map { abs($0 - (-4.152203)) < 0.0005 } == true,
                "stereo channels should resolve attenuation from the software scalar instead of the device dB curve",
                passed: &passed
            )

            let mixedZeroStereo = SystemOutputVolumeResolver.snapshot(
                muteValue: false,
                channels: [
                    .init(scalar: 0, decibels: -90),
                    .init(scalar: 1, decibels: 0)
                ],
                hasSoftwareVolume: true
            )
            try check(
                mixedZeroStereo == .init(isMuted: false, attenuationDB: 0),
                "mixed zero and nonzero stereo should stay audible and use the nonzero channel attenuation",
                passed: &passed
            )

            let zeroScalar = SystemOutputVolumeResolver.snapshot(
                muteValue: false,
                channels: [
                    .init(scalar: 0, decibels: -90)
                ],
                hasSoftwareVolume: true
            )
            try check(
                zeroScalar == .init(isMuted: true, attenuationDB: nil),
                "a zero scalar should resolve to muted even when the explicit mute property is false",
                passed: &passed
            )

            let explicitMute = SystemOutputVolumeResolver.snapshot(
                muteValue: true,
                channels: [
                    .init(scalar: 0.7, decibels: -10)
                ],
                hasSoftwareVolume: true
            )
            try check(
                explicitMute == .init(isMuted: true, attenuationDB: nil),
                "an explicit mute property should force a muted snapshot",
                passed: &passed
            )

            let passthrough = SystemOutputVolumeResolver.snapshot(
                muteValue: false,
                channels: [],
                hasSoftwareVolume: false
            )
            try check(
                passthrough == .init(isMuted: false, attenuationDB: nil),
                "devices without software volume properties should resolve to passthrough",
                passed: &passed
            )

            let asymmetric = SystemOutputVolumeResolver.snapshot(
                muteValue: false,
                channels: [
                    .init(scalar: 0.1, decibels: -20),
                    .init(scalar: 0.5, decibels: -40)
                ],
                hasSoftwareVolume: true
            )
            try check(
                !asymmetric.isMuted
                    && asymmetric.attenuationDB.map { abs($0 - (-6.0206)) < 0.0005 } == true,
                "asymmetric stereo should choose the louder scalar so shared compensation cannot overboost it",
                passed: &passed
            )

            let invalidMetadata = SystemOutputVolumeResolver.snapshot(
                muteValue: false,
                channels: [
                    .init(scalar: .nan, decibels: -30),
                    .init(scalar: 0.5, decibels: .infinity),
                    .init(scalar: -0.25, decibels: -12)
                ],
                hasSoftwareVolume: true
            )
            try check(
                !invalidMetadata.isMuted
                    && invalidMetadata.attenuationDB.map { abs($0 - (-6.0206)) < 0.0005 } == true,
                "invalid channel metadata should be ignored while valid scalars still drive attenuation",
                passed: &passed
            )

            let fallbackDecibels = SystemOutputVolumeResolver.snapshot(
                muteValue: false,
                channels: [
                    .init(scalar: 0.25, decibels: nil)
                ],
                hasSoftwareVolume: true
            )
            try check(
                !fallbackDecibels.isMuted &&
                    fallbackDecibels.attenuationDB.map { abs($0 - (-12.041201)) < 0.0005 } == true,
                "missing device dB conversion should fall back to 20*log10(scalar)",
                passed: &passed
            )

            let steepDeviceCurve = SystemOutputVolumeResolver.snapshot(
                muteValue: false,
                channels: [
                    .init(scalar: 0.3125, decibels: -68.75)
                ],
                hasSoftwareVolume: true
            )
            try check(
                !steepDeviceCurve.isMuted
                    && steepDeviceCurve.attenuationDB.map { abs($0 - (-10.103)) < 0.0005 } == true,
                "a steep hardware dB curve must not turn a 31% scalar into a +68 dB compensation request",
                passed: &passed
            )

            let maximum = KeyboardAbsoluteVolumeCompensation.plan(
                for: .init(isMuted: false, attenuationDB: 0)
            )
            try check(
                maximum == .init(
                    shouldPlay: true,
                    stageGainsDB: Array(repeating: 0, count: KeyboardAbsoluteVolumeCompensation.stageCount)
                ),
                "maximum output should keep playback enabled with five neutral gain stages",
                passed: &passed
            )

            let reduced = KeyboardAbsoluteVolumeCompensation.plan(
                for: .init(isMuted: false, attenuationDB: -37.75),
                playbackGain: 0.0001,
                samplePeak: 0.0001
            )
            try check(reduced.shouldPlay, "negative attenuation should still play keyboard audio", passed: &passed)
            try check(
                reduced.stageGainsDB.count == KeyboardAbsoluteVolumeCompensation.stageCount,
                "every compensation plan should emit exactly five stage gains",
                passed: &passed
            )
            try check(
                abs(reduced.stageGainsDB.reduce(0, +) - 37.75) < 0.001,
                "a -37.75 dB output attenuation should produce +37.75 dB total compensation",
                passed: &passed
            )
            try check(
                reduced.stageGainsDB.allSatisfy { (0...24).contains($0) },
                "every gain stage should stay inside the 0...24 dB range",
                passed: &passed
            )

            let headroomLimited = KeyboardAbsoluteVolumeCompensation.plan(
                for: .init(isMuted: false, attenuationDB: -37.75),
                playbackGain: 1,
                samplePeak: 0.25
            )
            try check(headroomLimited.shouldPlay, "headroom-limited playback should remain enabled", passed: &passed)
            try check(
                abs(headroomLimited.stageGainsDB.reduce(0, +) - 10.629579) < 0.001,
                "full keyboard gain should cap compensation to the clean headroom implied by the sample peak",
                passed: &passed
            )

            let quieterKeyboard = KeyboardAbsoluteVolumeCompensation.plan(
                for: .init(isMuted: false, attenuationDB: -37.75),
                playbackGain: 0.125,
                samplePeak: 0.25
            )
            try check(
                abs(quieterKeyboard.stageGainsDB.reduce(0, +) - 28.691378) < 0.001,
                "lower in-app keyboard gain should leave more clean compensation headroom available",
                passed: &passed
            )

            let hotterKeyboard = KeyboardAbsoluteVolumeCompensation.plan(
                for: .init(isMuted: false, attenuationDB: -37.75),
                playbackGain: 1,
                samplePeak: 0.57
            )
            try check(
                abs(hotterKeyboard.stageGainsDB.reduce(0, +) - 3.470882) < 0.001,
                "hotter recordings should leave less clean compensation headroom than quieter ones",
                passed: &passed
            )

            let hotSample = KeyboardAbsoluteVolumeCompensation.plan(
                for: .init(isMuted: false, attenuationDB: -12),
                playbackGain: 1,
                samplePeak: 1
            )
            try check(
                hotSample == maximum,
                "already-hot samples at full app gain should not receive extra compensation that would force clipping",
                passed: &passed
            )

            let hundredDB = KeyboardAbsoluteVolumeCompensation.plan(
                for: .init(isMuted: false, attenuationDB: -100),
                playbackGain: 0.0001,
                samplePeak: 0.0001
            )
            try check(hundredDB.shouldPlay, "large finite attenuation should still produce playback", passed: &passed)
            try check(
                abs(hundredDB.stageGainsDB.reduce(0, +) - 100) < 0.001,
                "a -100 dB attenuation should clamp to +100 dB total compensation",
                passed: &passed
            )
            try check(
                hundredDB.stageGainsDB.allSatisfy { (0...24).contains($0) },
                "large attenuation should still respect the per-stage 24 dB ceiling",
                passed: &passed
            )

            let firstBoundary = KeyboardAbsoluteVolumeCompensation.plan(
                for: .init(isMuted: false, attenuationDB: -24),
                playbackGain: 0.0001,
                samplePeak: 0.0001
            )
            try check(
                firstBoundary == .init(
                    shouldPlay: true,
                    stageGainsDB: [24, 0, 0, 0, 0]
                ),
                "an exact 24 dB attenuation should fill one stage to the boundary and leave the rest neutral",
                passed: &passed
            )

            let fullBoundary = KeyboardAbsoluteVolumeCompensation.plan(
                for: .init(isMuted: false, attenuationDB: -120),
                playbackGain: 0.0001,
                samplePeak: 0.0001
            )
            try check(
                fullBoundary == .init(
                    shouldPlay: true,
                    stageGainsDB: Array(repeating: 24, count: KeyboardAbsoluteVolumeCompensation.stageCount)
                ),
                "a full 120 dB compensation request should saturate all five 24 dB stages",
                passed: &passed
            )

            let beyondBoundary = KeyboardAbsoluteVolumeCompensation.plan(
                for: .init(isMuted: false, attenuationDB: -200),
                playbackGain: 0.0001,
                samplePeak: 0.0001
            )
            try check(
                beyondBoundary == fullBoundary,
                "attenuation below the supported floor should still clamp to five saturated 24 dB stages",
                passed: &passed
            )

            let unknownPeak = KeyboardAbsoluteVolumeCompensation.plan(
                for: .init(isMuted: false, attenuationDB: -24),
                playbackGain: 1,
                samplePeak: nil
            )
            try check(
                unknownPeak == maximum,
                "missing sample peak metadata should fail safe without positive compensation",
                passed: &passed
            )

            let muted = KeyboardAbsoluteVolumeCompensation.plan(
                for: .init(isMuted: true, attenuationDB: -40)
            )
            try check(
                muted == .init(
                    shouldPlay: false,
                    stageGainsDB: Array(repeating: 0, count: KeyboardAbsoluteVolumeCompensation.stageCount)
                ),
                "muted output should suppress playback and reset every stage to 0 dB",
                passed: &passed
            )

            let unsupported = KeyboardAbsoluteVolumeCompensation.plan(
                for: .init(isMuted: false, attenuationDB: nil)
            )
            try check(
                unsupported == .init(
                    shouldPlay: true,
                    stageGainsDB: Array(repeating: 0, count: KeyboardAbsoluteVolumeCompensation.stageCount)
                ),
                "unsupported output metadata should fall back to passthrough playback",
                passed: &passed
            )

            let positive = KeyboardAbsoluteVolumeCompensation.plan(
                for: .init(isMuted: false, attenuationDB: 6)
            )
            try check(
                positive == unsupported,
                "positive attenuation metadata should not add gain compensation",
                passed: &passed
            )

            for invalid in [Float.nan, .infinity, -.infinity] {
                let invalidPlan = KeyboardAbsoluteVolumeCompensation.plan(
                    for: .init(isMuted: false, attenuationDB: invalid)
                )
                try check(
                    invalidPlan == unsupported,
                    "non-finite attenuation metadata should fall back to passthrough playback",
                    passed: &passed
                )
            }

            print("Absolute volume core harness passed: \(passed) assertions")
        } catch {
            fputs("Absolute volume core harness FAILED: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func check(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        passed: inout Int
    ) throws {
        guard condition() else { throw AbsoluteVolumeHarnessFailure.assertion(message) }
        passed += 1
    }
}
