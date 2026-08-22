import Foundation

enum SoundPackResolutionSource: Hashable, Sendable {
    case keyOverride(KeyboardKeyID)
    case special(KeyboardSpecialKeyID)
    case row(KeyboardRowID)
    case generic
    case unavailableKey
    case missingAssignment
    case brokenAssetReference(SoundPackAssetID)
}

enum SoundPackResolution: Hashable, Sendable {
    case asset(SoundPackAssetID, source: SoundPackResolutionSource)
    case silent(source: SoundPackResolutionSource)
    case missing(source: SoundPackResolutionSource)

    var assetID: SoundPackAssetID? {
        guard case let .asset(assetID, _) = self else { return nil }
        return assetID
    }

    var isSilent: Bool {
        if case .silent = self { return true }
        return false
    }
}

struct SoundPackResolver: Sendable {
    let manifest: SoundPackManifest

    init(manifest: SoundPackManifest) {
        self.manifest = manifest
    }

    func resolution(
        for keyCode: UInt16,
        phase: KeySoundPhase
    ) -> SoundPackResolution {
        guard let key = KeyboardLayoutCatalog.key(for: keyCode), key.isAssignable else {
            return .missing(source: .unavailableKey)
        }
        let assignments = manifest.assignments(for: phase)

        if let override = assignments.override(for: key.id) {
            switch override {
            case .inherit:
                break
            case .silent:
                return .silent(source: .keyOverride(key.id))
            case let .asset(assetID):
                return resolution(
                    for: assetID,
                    source: .keyOverride(key.id)
                )
            }
        }

        if let specialKey = key.specialKey,
           let assetID = assignments.asset(for: specialKey) {
            return resolution(for: assetID, source: .special(specialKey))
        }

        if let assetID = assignments.asset(for: key.row) {
            return resolution(for: assetID, source: .row(key.row))
        }

        if let assetID = assignments.generic {
            return resolution(for: assetID, source: .generic)
        }

        return .missing(source: .missingAssignment)
    }

    func audioAsset(
        for keyCode: UInt16,
        phase: KeySoundPhase
    ) -> SoundPackAudioAsset? {
        guard let assetID = resolution(for: keyCode, phase: phase).assetID else {
            return nil
        }
        return manifest.assets[assetID.rawValue]
    }

    func resolutions(
        for keyCodes: some Sequence<UInt16>,
        phase: KeySoundPhase
    ) -> [UInt16: SoundPackResolution] {
        var result: [UInt16: SoundPackResolution] = [:]
        for keyCode in keyCodes {
            result[keyCode] = resolution(for: keyCode, phase: phase)
        }
        return result
    }

    private func resolution(
        for assetID: SoundPackAssetID,
        source: SoundPackResolutionSource
    ) -> SoundPackResolution {
        guard manifest.assets[assetID.rawValue] != nil else {
            return .missing(source: .brokenAssetReference(assetID))
        }
        return .asset(assetID, source: source)
    }
}
