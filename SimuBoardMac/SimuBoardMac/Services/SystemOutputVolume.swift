import Foundation

struct SystemOutputVolumeSnapshot: Equatable, Sendable {
    let isMuted: Bool
    let attenuationDB: Float?
}

struct KeyboardAbsoluteVolumePlan: Equatable, Sendable {
    let shouldPlay: Bool
    let stageGainsDB: [Float]
}

enum KeyboardAbsoluteVolumeCompensation {
    static let stageCount = 5
    static let maximumStageGainDB: Float = 24
    private static let maximumTotalGainDB = Float(stageCount) * maximumStageGainDB

    static func plan(for snapshot: SystemOutputVolumeSnapshot) -> KeyboardAbsoluteVolumePlan {
        guard !snapshot.isMuted else { return silentPlan }
        guard let attenuation = snapshot.attenuationDB, attenuation.isFinite, attenuation < 0 else {
            return passthroughPlan
        }
        return plan(totalGainDB: min(maximumTotalGainDB, -attenuation))
    }

    private static let silentPlan = KeyboardAbsoluteVolumePlan(
        shouldPlay: false,
        stageGainsDB: Array(repeating: 0, count: stageCount)
    )

    private static let passthroughPlan = KeyboardAbsoluteVolumePlan(
        shouldPlay: true,
        stageGainsDB: Array(repeating: 0, count: stageCount)
    )

    private static func plan(totalGainDB: Float) -> KeyboardAbsoluteVolumePlan {
        let clampedGain = max(0, min(maximumTotalGainDB, totalGainDB))
        var remainingGain = clampedGain
        var stageGains = Array(repeating: Float(0), count: stageCount)

        for index in stageGains.indices where remainingGain > 0 {
            let stageGain = min(maximumStageGainDB, remainingGain)
            stageGains[index] = stageGain
            remainingGain -= stageGain
        }

        return KeyboardAbsoluteVolumePlan(
            shouldPlay: true,
            stageGainsDB: stageGains
        )
    }
}
