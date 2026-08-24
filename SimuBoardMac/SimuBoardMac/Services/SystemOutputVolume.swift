import CoreAudio
import Foundation

struct SystemOutputVolumeSnapshot: Equatable, Sendable {
    let isMuted: Bool
    let attenuationDB: Float?
}

struct SystemOutputChannelVolume: Equatable, Sendable {
    let scalar: Float
    let decibels: Float?
}

enum SystemOutputVolumeResolver {
    static func snapshot(
        muteValue: Bool?,
        channels: [SystemOutputChannelVolume],
        hasSoftwareVolume: Bool
    ) -> SystemOutputVolumeSnapshot {
        if muteValue == true {
            return .init(isMuted: true, attenuationDB: nil)
        }

        guard hasSoftwareVolume else {
            return .init(isMuted: false, attenuationDB: nil)
        }

        var resolvedAttenuations = [Float]()
        resolvedAttenuations.reserveCapacity(channels.count)
        var sawValidScalar = false
        var sawNonZeroValidScalar = false

        for channel in channels {
            guard let scalar = validatedScalar(channel.scalar) else {
                continue
            }

            sawValidScalar = true

            if scalar == 0 {
                continue
            }

            sawNonZeroValidScalar = true

            let amplitudeAttenuation = Float(20 * Foundation.log10(Double(scalar)))
            guard amplitudeAttenuation.isFinite else {
                continue
            }
            resolvedAttenuations.append(amplitudeAttenuation)
        }

        if sawValidScalar, !sawNonZeroValidScalar {
            return .init(isMuted: true, attenuationDB: nil)
        }

        return .init(isMuted: false, attenuationDB: resolvedAttenuations.max())
    }

    private static func validatedScalar(_ scalar: Float) -> Float? {
        guard scalar.isFinite, scalar >= 0, scalar <= 1 else {
            return nil
        }

        return scalar
    }
}

protocol SystemOutputVolumeReading: Sendable {
    func snapshot() -> SystemOutputVolumeSnapshot
}

struct CoreAudioSystemOutputVolumeReader: SystemOutputVolumeReading {
    func snapshot() -> SystemOutputVolumeSnapshot {
        guard let deviceID = Self.defaultOutputDeviceID() else {
            return .init(isMuted: false, attenuationDB: nil)
        }

        let muteValue = Self.readMuteValue(for: deviceID)
        let preferredChannels = Self.preferredStereoChannels(for: deviceID)

        let preferredVolumes = Self.readVolumes(for: deviceID, elements: preferredChannels)
        if preferredVolumes.hasSoftwareVolume, !preferredVolumes.channels.isEmpty {
            return SystemOutputVolumeResolver.snapshot(
                muteValue: muteValue,
                channels: preferredVolumes.channels,
                hasSoftwareVolume: true
            )
        }

        let mainElementVolumes = Self.readVolumes(for: deviceID, elements: [Self.mainElement])
        if mainElementVolumes.hasSoftwareVolume, !mainElementVolumes.channels.isEmpty {
            return SystemOutputVolumeResolver.snapshot(
                muteValue: muteValue,
                channels: mainElementVolumes.channels,
                hasSoftwareVolume: true
            )
        }

        let fallbackVolumes = Self.readVolumes(for: deviceID, elements: [1, 2])
        return SystemOutputVolumeResolver.snapshot(
            muteValue: muteValue,
            channels: fallbackVolumes.channels,
            hasSoftwareVolume: fallbackVolumes.hasSoftwareVolume
        )
    }

    private static let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private static let outputScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
    private static let mainElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)

    private struct ChannelReadResult: Sendable {
        let channels: [SystemOutputChannelVolume]
        let hasSoftwareVolume: Bool
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        let address = propertyAddress(
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            element: mainElement
        )

        guard let deviceID: AudioDeviceID = readProperty(
            objectID: systemObjectID,
            address: address
        ) else {
            return nil
        }

        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            return nil
        }

        return deviceID
    }

    private static func readMuteValue(for deviceID: AudioDeviceID) -> Bool? {
        let address = propertyAddress(selector: kAudioDevicePropertyMute)
        guard hasProperty(objectID: deviceID, address: address),
              let rawMute: UInt32 = readProperty(objectID: deviceID, address: address) else {
            return nil
        }

        return rawMute != 0
    }

    private static func preferredStereoChannels(for deviceID: AudioDeviceID) -> [AudioObjectPropertyElement] {
        let address = propertyAddress(selector: kAudioDevicePropertyPreferredChannelsForStereo)
        guard hasProperty(objectID: deviceID, address: address),
              let channels = readChannelList(objectID: deviceID, address: address) else {
            return []
        }

        var seen = Set<AudioObjectPropertyElement>()
        return channels.compactMap { channel in
            let element = AudioObjectPropertyElement(channel)
            guard element > 0, seen.insert(element).inserted else {
                return nil
            }
            return element
        }
    }

    private static func readVolumes(
        for deviceID: AudioDeviceID,
        elements: [AudioObjectPropertyElement]
    ) -> ChannelReadResult {
        var observedChannels = [SystemOutputChannelVolume]()
        observedChannels.reserveCapacity(elements.count)
        var hasSoftwareVolume = false

        for element in elements {
            let scalarAddress = propertyAddress(
                selector: kAudioDevicePropertyVolumeScalar,
                element: element
            )
            guard hasProperty(objectID: deviceID, address: scalarAddress) else {
                continue
            }

            hasSoftwareVolume = true

            guard let scalar: Float = readProperty(objectID: deviceID, address: scalarAddress),
                  scalar.isFinite else {
                continue
            }

            let decibels = readDecibels(for: deviceID, scalar: scalar, element: element)
            observedChannels.append(.init(scalar: scalar, decibels: decibels))
        }

        return .init(channels: observedChannels, hasSoftwareVolume: hasSoftwareVolume)
    }

    private static func readDecibels(
        for deviceID: AudioDeviceID,
        scalar: Float,
        element: AudioObjectPropertyElement
    ) -> Float? {
        guard scalar != 0 else {
            return nil
        }

        let decibelAddress = propertyAddress(
            selector: kAudioDevicePropertyVolumeScalarToDecibels,
            element: element
        )
        guard hasProperty(objectID: deviceID, address: decibelAddress) else {
            return nil
        }

        var mutableDecibelAddress = decibelAddress
        var decibels = scalar
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(deviceID, &mutableDecibelAddress, 0, nil, &size, &decibels)
        guard status == noErr, size == UInt32(MemoryLayout<Float>.size), decibels.isFinite else {
            return nil
        }

        return decibels
    }

    private static func propertyAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = outputScope,
        element: AudioObjectPropertyElement = mainElement
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }

    private static func hasProperty(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress
    ) -> Bool {
        var address = address
        return AudioObjectHasProperty(objectID, &address)
    }

    private static func readProperty<T>(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress
    ) -> T? {
        var address = address
        return withUnsafeTemporaryAllocation(of: T.self, capacity: 1) { buffer in
            var size = UInt32(MemoryLayout<T>.size)
            let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, buffer.baseAddress!)
            guard status == noErr, size == UInt32(MemoryLayout<T>.size) else {
                return nil
            }

            return buffer.baseAddress!.pointee
        }
    }

    private static func readChannelList(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress
    ) -> [UInt32]? {
        var address = address
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size)
        guard sizeStatus == noErr, size >= UInt32(MemoryLayout<UInt32>.size) else {
            return nil
        }

        let channelCount = Int(size) / MemoryLayout<UInt32>.size
        var channels = Array(repeating: UInt32.zero, count: channelCount)
        let readStatus = channels.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, buffer.baseAddress!)
        }
        guard readStatus == noErr else {
            return nil
        }

        return channels
    }
}

struct KeyboardAbsoluteVolumePlan: Equatable, Sendable {
    let shouldPlay: Bool
    let stageGainsDB: [Float]
}

enum KeyboardAbsoluteVolumeCompensation {
    static let stageCount = 5
    static let maximumStageGainDB: Float = 24
    private static let maximumTotalGainDB = Float(stageCount) * maximumStageGainDB
    private static let safeOutputPeak: Float = 0.85

    static func plan(
        for snapshot: SystemOutputVolumeSnapshot,
        playbackGain: Float = 1,
        samplePeak: Float? = nil
    ) -> KeyboardAbsoluteVolumePlan {
        guard !snapshot.isMuted else { return silentPlan }
        guard let attenuation = snapshot.attenuationDB, attenuation.isFinite, attenuation < 0 else {
            return passthroughPlan
        }
        let requestedGainDB = min(maximumTotalGainDB, -attenuation)
        let cleanGainLimitDB = maximumCleanCompensationDB(
            playbackGain: playbackGain,
            samplePeak: samplePeak
        )
        return plan(totalGainDB: min(requestedGainDB, cleanGainLimitDB))
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

    private static func maximumCleanCompensationDB(
        playbackGain: Float,
        samplePeak: Float?
    ) -> Float {
        guard let samplePeak,
              samplePeak.isFinite,
              samplePeak > 0,
              playbackGain.isFinite,
              playbackGain > 0 else { return 0 }

        let clampedPlaybackGain = max(0, min(1, playbackGain))
        let projectedPeak = clampedPlaybackGain * samplePeak
        guard projectedPeak.isFinite, projectedPeak > 0 else { return 0 }

        let maximumGainDB = Float(
            20 * Foundation.log10(Double(safeOutputPeak / projectedPeak))
        )
        guard maximumGainDB.isFinite else { return 0 }

        return max(0, min(maximumTotalGainDB, maximumGainDB))
    }
}
