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
                for: .init(isMuted: false, attenuationDB: -37.75)
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

            let hundredDB = KeyboardAbsoluteVolumeCompensation.plan(
                for: .init(isMuted: false, attenuationDB: -100)
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
                for: .init(isMuted: false, attenuationDB: -24)
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
                for: .init(isMuted: false, attenuationDB: -120)
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
                for: .init(isMuted: false, attenuationDB: -200)
            )
            try check(
                beyondBoundary == fullBoundary,
                "attenuation below the supported floor should still clamp to five saturated 24 dB stages",
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
