import AVFAudio
import CoreGraphics
import Darwin
import Foundation

private enum HarnessFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case let .assertion(message): message
        }
    }
}

private struct HarnessResults {
    private(set) var passed = 0

    mutating func check(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard condition() else {
            throw HarnessFailure.assertion("\(file):\(line): \(message)")
        }
        passed += 1
    }

    mutating func expectError(
        _ message: String,
        _ operation: () throws -> Void,
        matches: (Error) -> Bool
    ) throws {
        do {
            try operation()
            throw HarnessFailure.assertion("Expected error: \(message)")
        } catch let failure as HarnessFailure {
            throw failure
        } catch {
            guard matches(error) else {
                throw HarnessFailure.assertion("Wrong error for \(message): \(error)")
            }
            passed += 1
        }
    }
}

private struct PCM16MonoWave {
    let sampleRate: Int
    let channels: Int
    let bitsPerSample: Int
    let samples: [Int16]

    init(contentsOf url: URL) throws {
        let bytes = [UInt8](try Data(contentsOf: url))
        guard bytes.count >= 12,
              Array(bytes[0..<4]) == Array("RIFF".utf8),
              Array(bytes[8..<12]) == Array("WAVE".utf8) else {
            throw HarnessFailure.assertion("invalid RIFF/WAVE header: \(url.path)")
        }

        func uint16(at offset: Int) -> UInt16 {
            UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }

        func uint32(at offset: Int) -> UInt32 {
            UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
        }

        var format: (audioFormat: UInt16, channels: UInt16, sampleRate: UInt32, bits: UInt16)?
        var sampleBytes: ArraySlice<UInt8>?
        var offset = 12
        while offset <= bytes.count - 8 {
            let chunkID = String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii)
            let chunkSize = Int(uint32(at: offset + 4))
            let payloadStart = offset + 8
            guard chunkSize <= bytes.count - payloadStart else {
                throw HarnessFailure.assertion("truncated WAV chunk in \(url.path)")
            }
            let payloadEnd = payloadStart + chunkSize

            switch chunkID {
            case "fmt ":
                guard chunkSize >= 16 else {
                    throw HarnessFailure.assertion("short WAV format chunk: \(url.path)")
                }
                format = (
                    audioFormat: uint16(at: payloadStart),
                    channels: uint16(at: payloadStart + 2),
                    sampleRate: uint32(at: payloadStart + 4),
                    bits: uint16(at: payloadStart + 14)
                )
            case "data":
                sampleBytes = bytes[payloadStart..<payloadEnd]
            default:
                break
            }

            offset = payloadEnd + (chunkSize & 1)
        }

        guard let format, let sampleBytes,
              format.audioFormat == 1,
              format.channels == 1,
              format.bits == 16,
              sampleBytes.count.isMultiple(of: 2) else {
            throw HarnessFailure.assertion("pointer WAV must be mono 16-bit PCM: \(url.path)")
        }

        var decoded = [Int16]()
        decoded.reserveCapacity(sampleBytes.count / 2)
        var sampleOffset = sampleBytes.startIndex
        while sampleOffset < sampleBytes.endIndex {
            let bits = UInt16(sampleBytes[sampleOffset])
                | (UInt16(sampleBytes[sampleOffset + 1]) << 8)
            decoded.append(Int16(bitPattern: bits))
            sampleOffset += 2
        }
        guard !decoded.isEmpty else {
            throw HarnessFailure.assertion("pointer WAV has no samples: \(url.path)")
        }

        sampleRate = Int(format.sampleRate)
        channels = Int(format.channels)
        bitsPerSample = Int(format.bits)
        samples = decoded
    }
}

private struct PointerSpectrumMetrics {
    let peakAmplitude: Double
    let rmsAmplitude: Double
    let tailRMSDBFS: Double
    let centroidHz: Double
    let energyAbove8KHz: Double

    init(wave: PCM16MonoWave) {
        let normalized = wave.samples.map { Double($0) / 32_768 }
        peakAmplitude = normalized.lazy.map(abs).max() ?? 0
        rmsAmplitude = sqrt(normalized.lazy.map { $0 * $0 }.reduce(0, +) / Double(normalized.count))

        let tailCount = min(max(wave.sampleRate / 1_000, 1), normalized.count)
        let tailEnergy = normalized.suffix(tailCount).lazy.map { $0 * $0 }.reduce(0, +)
            / Double(tailCount)
        let tailRMS = sqrt(tailEnergy)
        tailRMSDBFS = tailRMS > 0 ? 20 * log10(tailRMS) : -.infinity

        var fftSize = 1
        while fftSize < normalized.count {
            fftSize <<= 1
        }
        fftSize = max(fftSize, 2)

        var real = [Double](repeating: 0, count: fftSize)
        var imaginary = [Double](repeating: 0, count: fftSize)
        let windowDenominator = Double(max(normalized.count - 1, 1))
        for index in normalized.indices {
            let hann = 0.5 - 0.5 * cos(2 * .pi * Double(index) / windowDenominator)
            real[index] = normalized[index] * hann
        }
        Self.radix2FFT(real: &real, imaginary: &imaginary)

        let binWidth = Double(wave.sampleRate) / Double(fftSize)
        var totalEnergy = 0.0
        var weightedFrequency = 0.0
        var highFrequencyEnergy = 0.0
        for bin in 0...fftSize / 2 {
            let energy = real[bin] * real[bin] + imaginary[bin] * imaginary[bin]
            let frequency = Double(bin) * binWidth
            totalEnergy += energy
            weightedFrequency += frequency * energy
            if frequency >= 8_000 {
                highFrequencyEnergy += energy
            }
        }
        centroidHz = totalEnergy > 0 ? weightedFrequency / totalEnergy : 0
        energyAbove8KHz = totalEnergy > 0 ? highFrequencyEnergy / totalEnergy : 0
    }

    private static func radix2FFT(real: inout [Double], imaginary: inout [Double]) {
        precondition(real.count == imaginary.count && real.count.isPowerOfTwo)
        let count = real.count

        var reversed = 0
        if count > 1 {
            for index in 1..<count {
                var bit = count >> 1
                while reversed & bit != 0 {
                    reversed ^= bit
                    bit >>= 1
                }
                reversed ^= bit
                if index < reversed {
                    real.swapAt(index, reversed)
                    imaginary.swapAt(index, reversed)
                }
            }
        }

        var length = 2
        while length <= count {
            let angle = -2 * Double.pi / Double(length)
            let stepReal = cos(angle)
            let stepImaginary = sin(angle)
            let halfLength = length / 2
            var blockStart = 0
            while blockStart < count {
                var twiddleReal = 1.0
                var twiddleImaginary = 0.0
                for offset in 0..<halfLength {
                    let even = blockStart + offset
                    let odd = even + halfLength
                    let oddReal = real[odd] * twiddleReal - imaginary[odd] * twiddleImaginary
                    let oddImaginary = real[odd] * twiddleImaginary + imaginary[odd] * twiddleReal
                    let evenReal = real[even]
                    let evenImaginary = imaginary[even]
                    real[even] = evenReal + oddReal
                    imaginary[even] = evenImaginary + oddImaginary
                    real[odd] = evenReal - oddReal
                    imaginary[odd] = evenImaginary - oddImaginary

                    let nextTwiddleReal = twiddleReal * stepReal - twiddleImaginary * stepImaginary
                    twiddleImaginary = twiddleReal * stepImaginary + twiddleImaginary * stepReal
                    twiddleReal = nextTwiddleReal
                }
                blockStart += length
            }
            length <<= 1
        }
    }
}

private extension Int {
    var isPowerOfTwo: Bool {
        self > 0 && (self & (self - 1)) == 0
    }
}

private final class LockedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }
}

private actor FetchRecorder {
    private(set) var etags: [String?] = []
    private var responses: [Result<GitHubReleaseFetchResult, Error>]

    init(_ responses: [Result<GitHubReleaseFetchResult, Error>]) {
        self.responses = responses
    }

    func fetch(etag: String?) throws -> GitHubReleaseFetchResult {
        etags.append(etag)
        guard !responses.isEmpty else {
            throw GitHubReleaseClientError.invalidResponse
        }
        return try responses.removeFirst().get()
    }

    var callCount: Int { etags.count }
}

@main
private struct DIYCoreHarness {
    static func main() async {
        var results = HarnessResults()
        do {
            try testSemanticVersion(&results)
            try testPointerEventMapping(&results)
            try testPointerSettingsAndResources(&results)
            try testValidatorAndResolver(&results)
            try await testAudioLibraryAndArchive(&results)
            try await testAudioSplit(&results)
            try testEngineLoadFailureContract(&results)
            try await testUpdateCachingAndThrottling(&results)
            print("DIY core harness passed: \(results.passed) assertions")
        } catch {
            fputs("DIY core harness FAILED: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func testSemanticVersion(_ results: inout HarnessResults) throws {
        let ordered = [
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-alpha.beta",
            "1.0.0-beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0",
        ].compactMap(SemanticVersion.init)
        try results.check(ordered.count == 8, "all SemVer precedence fixtures should parse")
        try results.check(zip(ordered, ordered.dropFirst()).allSatisfy(<), "SemVer precedence must match 2.0.0")
        try results.check(SemanticVersion("v0.4.0")?.description == "0.4.0", "release tag prefix should parse")
        try results.check(
            SemanticVersion("1.2.3+build.1") == SemanticVersion("1.2.3+build.2"),
            "build metadata must not affect precedence equality"
        )

        for invalid in ["1.2", "01.2.3", "1.02.3", "1.2.03", "1.2.3-01", "1.2.3-", "1.2.3+", "1.2.3+bad_idea"] {
            try results.check(SemanticVersion(invalid) == nil, "invalid SemVer accepted: \(invalid)")
        }
    }

    @MainActor
    private static func testPointerEventMapping(_ results: inout HarnessResults) throws {
        let observedTypes = KeyboardMonitor.observedEventTypes
        try results.check(observedTypes.count == 9, "input tap should observe the expected event types exactly once")
        try results.check(Set(observedTypes.map(\.rawValue)).count == observedTypes.count, "input event mask must not contain duplicates")
        for eventType in observedTypes {
            let bit = CGEventMask(1) << eventType.rawValue
            try results.check(
                KeyboardMonitor.observedEventMask & bit != 0,
                "input event mask should contain \(eventType.rawValue)"
            )
        }
        for ignoredType in [CGEventType.mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel] {
            let bit = CGEventMask(1) << ignoredType.rawValue
            try results.check(
                KeyboardMonitor.observedEventMask & bit == 0,
                "movement, drag, and scroll events must remain outside the tap mask"
            )
        }

        guard let keyboardEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 12,
            keyDown: true
        ) else {
            throw HarnessFailure.assertion("could not create keyboard CGEvent fixture")
        }
        keyboardEvent.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        guard case let .keyboard(decodedKeyboard)? = KeyboardMonitor.decodedInputEvent(
            type: .keyDown,
            event: keyboardEvent
        ) else {
            throw HarnessFailure.assertion("key-down CGEvent should decode as keyboard input")
        }
        try results.check(
            decodedKeyboard == KeyboardEvent(kind: .keyDown, keyCode: 12, isRepeat: true),
            "keyboard decoding should retain key code and repeat state"
        )

        keyboardEvent.flags = [.maskCommand]
        guard case let .keyboard(decodedShortcut)? = KeyboardMonitor.decodedInputEvent(
            type: .keyDown,
            event: keyboardEvent
        ) else {
            throw HarnessFailure.assertion("shortcut key-down should decode as keyboard input")
        }
        try results.check(
            decodedShortcut == KeyboardEvent(
                kind: .keyDown,
                keyCode: 12,
                isRepeat: true,
                isShortcutModified: true
            ),
            "keyboard decoding should retain Command/Control shortcut state"
        )

        let pointerFixtures: [(CGEventType, CGMouseButton, Int64?, PointerEvent)] = [
            (.leftMouseDown, .left, nil, PointerEvent(phase: .press, button: .primary)),
            (.leftMouseUp, .left, nil, PointerEvent(phase: .release, button: .primary)),
            (.rightMouseDown, .right, nil, PointerEvent(phase: .press, button: .secondary)),
            (.rightMouseUp, .right, nil, PointerEvent(phase: .release, button: .secondary)),
            (.otherMouseDown, .center, nil, PointerEvent(phase: .press, button: .middle)),
            (.otherMouseUp, .center, nil, PointerEvent(phase: .release, button: .middle)),
            (.otherMouseDown, .center, 4, PointerEvent(phase: .press, button: .auxiliary(4))),
            (.otherMouseUp, .center, 5, PointerEvent(phase: .release, button: .auxiliary(5))),
        ]
        for (eventType, mouseButton, buttonNumber, expected) in pointerFixtures {
            guard let event = CGEvent(
                mouseEventSource: nil,
                mouseType: eventType,
                mouseCursorPosition: .zero,
                mouseButton: mouseButton
            ) else {
                throw HarnessFailure.assertion("could not create pointer CGEvent fixture")
            }
            if let buttonNumber {
                event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
            }
            guard case let .pointer(decoded)? = KeyboardMonitor.decodedInputEvent(type: eventType, event: event) else {
                throw HarnessFailure.assertion("pointer CGEvent should decode as pointer input")
            }
            try results.check(decoded == expected, "pointer phase/button mapping should match the CGEvent type")
        }

        try results.check(PointerButton(mouseButtonNumber: 0) == .primary, "button 0 should be primary")
        try results.check(PointerButton(mouseButtonNumber: 1) == .secondary, "button 1 should be secondary")
        try results.check(PointerButton(mouseButtonNumber: 2) == .middle, "button 2 should be middle")
        try results.check(PointerButton(mouseButtonNumber: 8) == .auxiliary(8), "higher button numbers should remain identifiable")
        try results.check(PointerButton.secondary.sample == .secondary, "secondary button should request its semantic sample")
        try results.check(PointerButton.middle.sample == .middle, "middle button should request its semantic sample")

        guard let ignoredEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: .zero,
            mouseButton: .left
        ) else {
            throw HarnessFailure.assertion("could not create ignored CGEvent fixture")
        }
        try results.check(
            KeyboardMonitor.decodedInputEvent(type: .mouseMoved, event: ignoredEvent) == nil,
            "unobserved mouse movement should not decode into input audio"
        )
    }

    @MainActor
    private static func testPointerSettingsAndResources(
        _ results: inout HarnessResults
    ) throws {
        let suiteName = "SimuBoard.DIYCoreHarness.PointerSettings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw HarnessFailure.assertion("could not create pointer-settings UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = AppSettings(defaults: defaults)
        try results.check(!initial.isPointerSoundEnabled, "pointer sounds should be opt-in")
        try results.check(!initial.isTypingStatsEnabled, "persistent input statistics should be opt-in")
        try results.check(initial.selectedPointerProfile == .classic, "classic should be the default pointer profile")
        try results.check(initial.playsPointerReleaseSound, "pointer release sound should default to enabled")
        try results.check(
            abs(initial.pointerVolume - (0.42 * 0.65)) < 0.000_001,
            "a new pointer volume should start at 65% of the keyboard volume"
        )
        try results.check(
            abs(defaults.double(forKey: "pointerVolume") - initial.pointerVolume) < 0.000_001,
            "the migrated pointer volume should be persisted immediately"
        )

        initial.isPointerSoundEnabled = true
        initial.selectedPointerProfile = .glass
        initial.playsPointerReleaseSound = false
        initial.volume = 0.78
        initial.pointerVolume = 0.24
        initial.isTypingStatsEnabled = true
        let reloaded = AppSettings(defaults: defaults)
        try results.check(reloaded.isPointerSoundEnabled, "pointer enabled state should persist")
        try results.check(reloaded.selectedPointerProfile == .glass, "pointer profile should persist")
        try results.check(!reloaded.playsPointerReleaseSound, "pointer release preference should persist")
        try results.check(abs(reloaded.volume - 0.78) < 0.000_001, "keyboard volume should persist independently")
        try results.check(abs(reloaded.pointerVolume - 0.24) < 0.000_001, "pointer volume should persist independently")
        try results.check(reloaded.isTypingStatsEnabled, "typing statistics opt-in should persist")

        defaults.set("missing-future-profile", forKey: "selectedPointerProfile")
        let repaired = AppSettings(defaults: defaults)
        try results.check(
            repaired.selectedPointerProfileID == PointerSoundProfile.classic.rawValue,
            "an invalid persisted pointer profile should normalize to classic"
        )
        try results.check(
            defaults.string(forKey: "selectedPointerProfile") == PointerSoundProfile.classic.rawValue,
            "pointer profile normalization should repair persisted storage"
        )

        let migrationSuiteName = "SimuBoard.DIYCoreHarness.PointerVolumeMigration.\(UUID().uuidString)"
        guard let migrationDefaults = UserDefaults(suiteName: migrationSuiteName) else {
            throw HarnessFailure.assertion("could not create pointer-volume migration UserDefaults")
        }
        defer { migrationDefaults.removePersistentDomain(forName: migrationSuiteName) }
        migrationDefaults.set(0.8, forKey: "volume")
        let migrated = AppSettings(defaults: migrationDefaults)
        try results.check(
            abs(migrated.pointerVolume - 0.52) < 0.000_001,
            "an existing keyboard volume should seed pointer volume at 65% exactly once"
        )
        migrated.volume = 0.4
        let migratedReloaded = AppSettings(defaults: migrationDefaults)
        try results.check(
            abs(migratedReloaded.volume - 0.4) < 0.000_001
                && abs(migratedReloaded.pointerVolume - 0.52) < 0.000_001,
            "changing keyboard volume after migration must not change pointer volume"
        )

        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let pointerRoot = projectRoot.appendingPathComponent(
            "SimuBoardMac/SimuBoardMac/Resources/Audio/pointer",
            isDirectory: true
        )
        let spectralLimits: [PointerSoundProfile: (centroidHz: Double, energyAbove8KHz: Double)] = [
            .heavy: (4_250, 0.005),
            .silent: (4_800, 0.010),
            .classic: (6_200, 0.090),
            .crisp: (6_750, 0.130),
            .glass: (7_200, 0.200),
        ]
        var expectedPaths = Set<String>()
        var spectra: [PointerSoundProfile: [PointerSpectrumMetrics]] = [:]
        for profile in PointerSoundProfile.allCases {
            for phase in PointerSoundPhase.allCases {
                let relativePath = "\(profile.rawValue)/\(phase.rawValue)/PRIMARY.wav"
                expectedPaths.insert(relativePath)
                let sampleURL = pointerRoot.appendingPathComponent(relativePath)
                let info = try AudioImportService.validateNormalizedAudio(at: sampleURL)
                try results.check(
                    (0.02...0.15).contains(info.durationSeconds),
                    "pointer sample duration should remain click-like: \(relativePath)"
                )

                let wave = try PCM16MonoWave(contentsOf: sampleURL)
                try results.check(
                    wave.sampleRate == 48_000 && wave.channels == 1 && wave.bitsPerSample == 16,
                    "pointer WAV must remain 48 kHz mono signed 16-bit PCM: \(relativePath)"
                )
                let spectrum = PointerSpectrumMetrics(wave: wave)
                try results.check(
                    spectrum.peakAmplitude > 0.001 && spectrum.rmsAmplitude > 0.000_1,
                    "pointer WAV must not become silent: \(relativePath)"
                )
                try results.check(
                    spectrum.peakAmplitude < 0.95,
                    "pointer WAV peak must retain clipping headroom: \(relativePath)"
                )
                try results.check(
                    wave.samples.last == 0,
                    "pointer WAV must end at an exact zero crossing: \(relativePath)"
                )
                try results.check(
                    spectrum.tailRMSDBFS < -60,
                    "pointer WAV final 1 ms must stay below -60 dBFS: \(relativePath)"
                )
                try results.check(
                    spectrum.centroidHz.isFinite && spectrum.centroidHz > 0
                        && spectrum.energyAbove8KHz.isFinite
                        && (0...1).contains(spectrum.energyAbove8KHz),
                    "pointer WAV spectrum must be finite and non-empty: \(relativePath)"
                )
                spectra[profile, default: []].append(spectrum)
            }
        }

        let bundledPaths = try FileManager.default.subpathsOfDirectory(atPath: pointerRoot.path)
            .filter { $0.hasSuffix(".wav") }
        try results.check(
            Set(bundledPaths) == expectedPaths,
            "pointer resource tree should contain exactly one press/release pair per profile"
        )

        var centroidByProfile: [PointerSoundProfile: Double] = [:]
        var highFrequencyEnergyByProfile: [PointerSoundProfile: Double] = [:]
        for profile in PointerSoundProfile.allCases {
            guard let profileSpectra = spectra[profile], profileSpectra.count == PointerSoundPhase.allCases.count,
                  let limits = spectralLimits[profile] else {
                throw HarnessFailure.assertion("missing pointer spectrum fixtures for \(profile.rawValue)")
            }
            let meanCentroid = profileSpectra.map(\.centroidHz).reduce(0, +) / Double(profileSpectra.count)
            let meanHighFrequencyEnergy = profileSpectra.map(\.energyAbove8KHz).reduce(0, +)
                / Double(profileSpectra.count)
            centroidByProfile[profile] = meanCentroid
            highFrequencyEnergyByProfile[profile] = meanHighFrequencyEnergy
            try results.check(
                meanCentroid < limits.centroidHz,
                "\(profile.rawValue) mean spectral centroid is too sharp: "
                    + String(format: "%.0f Hz (limit %.0f Hz)", meanCentroid, limits.centroidHz)
            )
            try results.check(
                meanHighFrequencyEnergy < limits.energyAbove8KHz,
                "\(profile.rawValue) mean energy above 8 kHz is too high: "
                    + String(
                        format: "%.2f%% (limit %.2f%%)",
                        meanHighFrequencyEnergy * 100,
                        limits.energyAbove8KHz * 100
                    )
            )
        }

        let toneOrder: [PointerSoundProfile] = [.heavy, .silent, .classic, .crisp, .glass]
        let orderedCentroids = toneOrder.compactMap { centroidByProfile[$0] }
        let orderedHighFrequencyEnergy = toneOrder.compactMap { highFrequencyEnergyByProfile[$0] }
        try results.check(
            zip(orderedCentroids, orderedCentroids.dropFirst()).allSatisfy(<),
            "pointer profiles should retain their low-to-bright spectral-centroid order"
        )
        try results.check(
            zip(orderedHighFrequencyEnergy, orderedHighFrequencyEnergy.dropFirst()).allSatisfy(<),
            "pointer profiles should retain their low-to-bright high-frequency energy order"
        )
        try results.check(
            orderedCentroids.sorted()[orderedCentroids.count / 2] < 6_000,
            "the median pointer profile must remain comfortably below a 6 kHz spectral centroid"
        )
    }

    private static func testValidatorAndResolver(_ results: inout HarnessResults) throws {
        let overrideID = soundAssetID("a")
        let specialID = soundAssetID("b")
        let rowID = soundAssetID("c")
        let genericID = soundAssetID("d")
        let assets = Dictionary(uniqueKeysWithValues: [overrideID, specialID, rowID, genericID].map {
            ($0.rawValue, fakeAsset(id: $0))
        })

        var press = SoundPackPhaseAssignments(generic: genericID)
        press.setAsset(rowID, for: .r2)
        press.setAsset(specialID, for: .space)
        press.setOverride(.asset(overrideID), for: KeyboardKeyID("a"))
        var manifest = SoundPackManifest(
            name: "Resolver fixture",
            baseProfileID: SwitchProfile.mxBlue.rawValue,
            press: press,
            assets: assets
        )
        try SoundPackValidator.validate(manifest)
        var resolver = SoundPackResolver(manifest: manifest)

        try results.check(
            resolver.resolution(for: 0, phase: .press) == .asset(overrideID, source: .keyOverride(KeyboardKeyID("a"))),
            "per-key override must beat row and generic"
        )
        try results.check(
            resolver.resolution(for: 49, phase: .press) == .asset(specialID, source: .special(.space)),
            "special assignment must beat row and generic"
        )
        try results.check(
            resolver.resolution(for: 1, phase: .press) == .asset(rowID, source: .row(.r2)),
            "row assignment must beat generic"
        )
        try results.check(
            resolver.resolution(for: 12, phase: .press) == .asset(genericID, source: .generic),
            "generic assignment should be the final custom fallback"
        )

        manifest.press.setOverride(.inherit, for: KeyboardKeyID("a"))
        resolver = SoundPackResolver(manifest: manifest)
        try results.check(
            resolver.resolution(for: 0, phase: .press) == .asset(rowID, source: .row(.r2)),
            "inherit must continue resolving through row"
        )

        manifest.press.setOverride(.silent, for: KeyboardKeyID("a"))
        resolver = SoundPackResolver(manifest: manifest)
        try results.check(
            resolver.resolution(for: 0, phase: .press) == .silent(source: .keyOverride(KeyboardKeyID("a"))),
            "explicit silence must prevent lower-level fallback"
        )
        try results.check(
            resolver.resolution(for: 63, phase: .press) == .asset(genericID, source: .generic),
            "Fn/Globe should participate in DIY mapping when delivered as flagsChanged"
        )

        let fallbackManifest = SoundPackManifest(
            name: "Built-in fallback fixture",
            baseProfileID: SwitchProfile.mxClear.rawValue
        )
        try results.check(
            SoundPackResolver(manifest: fallbackManifest).resolution(for: 0, phase: .press)
                == .missing(source: .missingAssignment),
            "unassigned custom slots must remain missing so the engine can reach the built-in fallback"
        )
        try results.check(
            KeySoundMapper.sample(for: 0, phase: .release, profile: .mxClear) == .genericR2,
            "built-in fallback should retain the base profile's row-specific release mapping"
        )

        var broken = manifest
        broken.assets.removeValue(forKey: overrideID.rawValue)
        broken.press.setOverride(.asset(overrideID), for: KeyboardKeyID("a"))
        try results.check(
            SoundPackResolver(manifest: broken).resolution(for: 0, phase: .press)
                == .missing(source: .brokenAssetReference(overrideID)),
            "resolver must not return an absent asset"
        )

        var missingAsset = manifest
        missingAsset.assets.removeValue(forKey: overrideID.rawValue)
        missingAsset.press.setOverride(.asset(overrideID), for: KeyboardKeyID("a"))
        try results.expectError("validator rejects missing asset", {
            try SoundPackValidator.validate(missingAsset)
        }, matches: {
            if case SoundPackError.missingAsset = $0 { return true }
            return false
        })

        var unknownRow = manifest
        unknownRow.press.rows["R99"] = genericID
        try results.expectError("validator rejects unknown row", {
            try SoundPackValidator.validate(unknownRow)
        }, matches: {
            if case SoundPackError.invalidManifest = $0 { return true }
            return false
        })

        var unsafePath = manifest
        unsafePath.assets[genericID.rawValue]?.relativePath = "../escape.wav"
        try results.expectError("validator rejects traversal path", {
            try SoundPackValidator.validate(unsafePath)
        }, matches: {
            if case SoundPackError.unsafePath = $0 { return true }
            return false
        })

        var unknownBase = manifest
        unknownBase.baseProfileID = "unknown-profile"
        try results.expectError("validator rejects unknown built-in fallback", {
            try SoundPackValidator.validate(unknownBase)
        }, matches: {
            if case SoundPackError.invalidManifest = $0 { return true }
            return false
        })

        var unknownLayout = manifest
        unknownLayout.layoutID = "future-iso-layout"
        try results.expectError("validator rejects unsupported layout", {
            try SoundPackValidator.validate(unknownLayout)
        }, matches: {
            if case SoundPackError.invalidManifest = $0 { return true }
            return false
        })

        var excessiveDuration = SoundPackManifest(name: "Excessive duration")
        for index in 1...37 {
            let rawID = String(format: "%064x", index)
            let id = SoundPackAssetID(rawID)
            excessiveDuration.assets[rawID] = SoundPackAudioAsset(
                id: id,
                relativePath: "assets/\(rawID).wav",
                sha256: rawID,
                durationSeconds: 5,
                byteCount: 480_044
            )
        }
        try results.expectError("validator rejects excessive total audio duration", {
            try SoundPackValidator.validate(excessiveDuration)
        }, matches: {
            if case SoundPackError.sizeLimitExceeded = $0 { return true }
            return false
        })
    }

    private static func testAudioLibraryAndArchive(_ results: inout HarnessResults) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimuBoard-DIYCoreHarness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let boundedPCMBytes = try AudioImportService.checkedDecodedPCMByteCount(
            sampleRate: 48_000,
            channelCount: 2,
            frameLength: 48_000,
            bytesPerSample: 4
        )
        try results.check(boundedPCMBytes == 384_000, "decoded PCM byte count should include every channel")

        let framesAtMemoryLimit = AudioImportService.maximumDecodedPCMBytes / (8 * 8)
        let exactMemoryLimit = try AudioImportService.checkedDecodedPCMByteCount(
            sampleRate: 384_000,
            channelCount: 8,
            frameLength: framesAtMemoryLimit,
            bytesPerSample: 8
        )
        try results.check(
            exactMemoryLimit == AudioImportService.maximumDecodedPCMBytes,
            "decoded PCM allocation should allow the exact 64 MiB boundary"
        )
        try results.expectError("decoded PCM allocation rejects memory amplification", {
            _ = try AudioImportService.checkedDecodedPCMByteCount(
                sampleRate: 384_000,
                channelCount: 8,
                frameLength: framesAtMemoryLimit + 1,
                bytesPerSample: 8
            )
        }, matches: {
            if case SoundPackError.sizeLimitExceeded = $0 { return true }
            return false
        })
        try results.expectError("decoded PCM allocation rejects excessive channels", {
            _ = try AudioImportService.checkedDecodedPCMByteCount(
                sampleRate: 48_000,
                channelCount: 9,
                frameLength: 48_000,
                bytesPerSample: 4
            )
        }, matches: {
            if case SoundPackError.invalidAudio = $0 { return true }
            return false
        })
        try results.expectError("decoded PCM allocation rejects excessive sample rates", {
            _ = try AudioImportService.checkedDecodedPCMByteCount(
                sampleRate: 768_000,
                channelCount: 1,
                frameLength: 48_000,
                bytesPerSample: 4
            )
        }, matches: {
            if case SoundPackError.invalidAudio = $0 { return true }
            return false
        })
        try results.expectError("decoded PCM arithmetic cannot overflow", {
            _ = try AudioImportService.checkedDecodedPCMByteCount(
                sampleRate: 48_000,
                channelCount: 8,
                frameLength: Int64(AVAudioFrameCount.max),
                bytesPerSample: Int.max
            )
        }, matches: {
            if case SoundPackError.sizeLimitExceeded = $0 { return true }
            return false
        })

        let sourceURL = root.appendingPathComponent("source-44k-stereo.wav")
        try makeStereoFixture(at: sourceURL, sampleRate: 44_100, duration: 0.12)

        let importsRoot = root.appendingPathComponent("imports", isDirectory: true)
        let importer = AudioImportService(workingDirectory: importsRoot)
        let prepared = try await importer.prepareImport(from: sourceURL)
        let normalizedInfo = try AudioImportService.validateNormalizedAudio(at: prepared.normalizedFileURL)
        try results.check(normalizedInfo.sampleRate == 48_000, "import must normalize to 48 kHz")
        try results.check(normalizedInfo.channelCount == 1, "import must normalize to mono")
        try results.check(abs(normalizedInfo.durationSeconds - 0.12) < 0.003, "normalization should preserve duration")
        try results.check(prepared.metadata.sha256 == prepared.id.rawValue, "asset ID must be content hash")

        let duplicatePreparation = try await importer.prepareImport(from: sourceURL)
        try results.check(duplicatePreparation.id == prepared.id, "same normalized content should deduplicate")
        try results.check(
            duplicatePreparation.normalizedFileURL == prepared.normalizedFileURL,
            "deduplicated preparations should reuse the normalized file"
        )

        let invalidSourceURL = root.appendingPathComponent("invalid-compressed-audio.mp3")
        try Data("not an audio file".utf8).write(to: invalidSourceURL)

        let timeoutPIDURL = root.appendingPathComponent("timeout-ffmpeg.pid")
        let timeoutExecutableURL = root.appendingPathComponent("timeout-ffmpeg")
        try makeSleepingExecutable(at: timeoutExecutableURL, pidFileURL: timeoutPIDURL)
        let timeoutImportsRoot = root.appendingPathComponent("timeout-imports", isDirectory: true)
        let timeoutImporter = AudioImportService(
            workingDirectory: timeoutImportsRoot,
            ffmpegExecutableOverride: timeoutExecutableURL,
            ffmpegTimeoutSeconds: 0.5
        )
        let timeoutStartedAt = ProcessInfo.processInfo.systemUptime
        do {
            _ = try await timeoutImporter.prepareImport(from: invalidSourceURL)
            throw HarnessFailure.assertion("ffmpeg timeout fixture unexpectedly imported")
        } catch let error as SoundPackError {
            guard case let .invalidAudio(message) = error, message.contains("超时") else {
                throw HarnessFailure.assertion("wrong ffmpeg timeout error: \(error)")
            }
            try results.check(true, "ffmpeg fallback should report a bounded timeout")
        }
        let timeoutElapsed = ProcessInfo.processInfo.systemUptime - timeoutStartedAt
        try results.check(timeoutElapsed < 3, "ffmpeg timeout must return promptly")
        let timeoutPID = try readProcessIdentifier(at: timeoutPIDURL)
        try results.check(!processExists(timeoutPID), "timed-out ffmpeg process must be terminated")
        let timeoutLeftovers = try FileManager.default.contentsOfDirectory(
            at: timeoutImportsRoot,
            includingPropertiesForKeys: nil
        )
        try results.check(timeoutLeftovers.isEmpty, "timed-out ffmpeg output must be removed")

        try FileManager.default.removeItem(at: timeoutPIDURL)
        let playlistURL = root.appendingPathComponent("network-playlist.m3u")
        try Data("https://example.invalid/secret.mp3\n".utf8).write(to: playlistURL)
        do {
            _ = try await timeoutImporter.prepareImport(from: playlistURL)
            throw HarnessFailure.assertion("playlist unexpectedly reached fallback conversion")
        } catch let error as SoundPackError {
            guard case .invalidAudio = error else {
                throw HarnessFailure.assertion("wrong playlist rejection error: \(error)")
            }
            try results.check(true, "ffmpeg fallback should reject playlist containers")
        }
        try results.check(
            !FileManager.default.fileExists(atPath: timeoutPIDURL.path),
            "rejected playlists must not start the external converter"
        )

        let cancellationPIDURL = root.appendingPathComponent("cancelled-ffmpeg.pid")
        let cancellationExecutableURL = root.appendingPathComponent("cancelled-ffmpeg")
        try makeSleepingExecutable(at: cancellationExecutableURL, pidFileURL: cancellationPIDURL)
        let cancellationImportsRoot = root.appendingPathComponent("cancelled-imports", isDirectory: true)
        let cancellationImporter = AudioImportService(
            workingDirectory: cancellationImportsRoot,
            ffmpegExecutableOverride: cancellationExecutableURL,
            ffmpegTimeoutSeconds: 20
        )
        let cancellationTask = Task<PreparedSoundPackAudio, Error> {
            try await cancellationImporter.prepareImport(from: invalidSourceURL)
        }
        let fallbackStarted = await waitForFile(at: cancellationPIDURL, timeoutSeconds: 2)
        guard fallbackStarted else {
            cancellationTask.cancel()
            _ = try? await cancellationTask.value
            throw HarnessFailure.assertion("ffmpeg cancellation fixture did not start")
        }
        let cancellationPID = try readProcessIdentifier(at: cancellationPIDURL)
        let cancellationStartedAt = ProcessInfo.processInfo.systemUptime
        cancellationTask.cancel()
        do {
            _ = try await cancellationTask.value
            throw HarnessFailure.assertion("cancelled ffmpeg import unexpectedly succeeded")
        } catch is CancellationError {
            try results.check(true, "ffmpeg fallback should preserve task cancellation")
        }
        let cancellationElapsed = ProcessInfo.processInfo.systemUptime - cancellationStartedAt
        try results.check(cancellationElapsed < 3, "cancelled ffmpeg import must return promptly")
        try results.check(!processExists(cancellationPID), "cancelled ffmpeg process must be terminated")
        let cancellationLeftovers = try FileManager.default.contentsOfDirectory(
            at: cancellationImportsRoot,
            includingPropertiesForKeys: nil
        )
        try results.check(cancellationLeftovers.isEmpty, "cancelled ffmpeg output must be removed")

        var assignments = SoundPackPhaseAssignments(generic: prepared.id)
        assignments.setAsset(prepared.id, for: .space)
        let packID = UUID()
        let manifest = SoundPackManifest(
            id: packID,
            name: "Round trip",
            baseProfileID: SwitchProfile.holyPanda.rawValue,
            press: assignments,
            release: SoundPackPhaseAssignments(generic: prepared.id),
            assets: [prepared.id.rawValue: prepared.metadata]
        )

        let libraryRoot = root.appendingPathComponent("library", isDirectory: true)
        let library = SoundPackLibrary(rootURL: libraryRoot, builtInDescriptors: [])
        let descriptor = try await library.save(
            manifest: manifest,
            assetFiles: [prepared.id: prepared.normalizedFileURL]
        )
        try results.check(descriptor.customPackID == packID, "save should preserve pack UUID")
        let loaded = try await library.loadCustomPack(id: packID)
        try results.check(loaded.manifest.name == "Round trip", "saved manifest should load")
        let loadedAssetURL = try loaded.assetURL(for: prepared.id)
        let loadedAssetHash = try SoundPackFileUtilities.sha256(of: loadedAssetURL)
        try results.check(
            loadedAssetHash == prepared.id.rawValue,
            "saved audio hash should survive library round trip"
        )
        let initialDescriptors = try await library.descriptors()
        try results.check(initialDescriptors.count == 1, "library should enumerate saved custom pack")

        var renamed = loaded.manifest
        renamed.name = "Round trip renamed"
        _ = try await library.save(manifest: renamed)
        let reloadedAfterRename = try await library.loadCustomPack(id: packID)
        try results.check(
            reloadedAfterRename.manifest.name == "Round trip renamed",
            "updating metadata should retain existing asset files"
        )

        let archive = SoundPackArchiveService()
        let exportURL = root.appendingPathComponent("export.simuboardpack", isDirectory: true)
        _ = try await archive.export(customPackID: packID, from: library, to: exportURL)
        _ = try await archive.validate(at: exportURL)
        try results.check(FileManager.default.fileExists(atPath: exportURL.path), "export should create package")

        // Exporting over an existing package exercises the atomic replacement path.
        _ = try await archive.export(customPackID: packID, from: library, to: exportURL)
        _ = try await archive.validate(at: exportURL)
        try results.check(true, "re-export over an existing package should remain valid")

        let importedLibrary = SoundPackLibrary(
            rootURL: root.appendingPathComponent("imported-library", isDirectory: true),
            builtInDescriptors: []
        )
        let imported = try await archive.importPack(at: exportURL, into: importedLibrary)
        try results.check(imported.customPackID == packID, "first import should retain package UUID")

        do {
            _ = try await archive.importPack(
                at: exportURL,
                into: importedLibrary,
                collisionPolicy: .reject
            )
            throw HarnessFailure.assertion("reject collision policy accepted a duplicate UUID")
        } catch SoundPackError.packAlreadyExists(let rejectedID) {
            try results.check(rejectedID == packID, "reject collision should report colliding UUID")
        }

        let duplicated = try await archive.importPack(
            at: exportURL,
            into: importedLibrary,
            collisionPolicy: .duplicate
        )
        try results.check(duplicated.customPackID != packID, "duplicate collision should mint a new UUID")
        let duplicatedDescriptors = try await importedLibrary.descriptors()
        try results.check(duplicatedDescriptors.count == 2, "duplicate import should preserve both packs")

        let exportedManifestURL = exportURL.appendingPathComponent("manifest.json")
        var replacementManifest = try SoundPackCoding.decode(Data(contentsOf: exportedManifestURL))
        replacementManifest.name = "Collision replacement"
        try SoundPackCoding.encode(replacementManifest).write(to: exportedManifestURL, options: .atomic)
        _ = try await archive.validate(at: exportURL)
        _ = try await archive.importPack(
            at: exportURL,
            into: importedLibrary,
            collisionPolicy: .replace
        )
        let replacedDescriptors = try await importedLibrary.descriptors()
        try results.check(replacedDescriptors.count == 2, "replace collision should not add a third pack")
        let replacedDocument = try await importedLibrary.loadCustomPack(id: packID)
        try results.check(
            replacedDocument.manifest.name == "Collision replacement",
            "replace collision should update the existing package contents"
        )
    }

    private static func testAudioSplit(_ results: inout HarnessResults) async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "SimuBoardSplitHarness-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("complete-keystroke.wav")
        try makeStereoFixture(at: source, sampleRate: 44_100, duration: 0.16)

        let splitter = AudioSplitService()
        let analysis = try await splitter.analyze(sourceURL: source)
        try results.check(analysis.sampleRate == 48_000, "split analysis should normalize to 48 kHz")
        try results.check(analysis.frameCount > 0, "split analysis should produce samples")
        try results.check(
            analysis.suggestion.splitTime > 0 && analysis.suggestion.splitTime < analysis.duration,
            "split suggestion should stay inside the recording"
        )

        let press = root.appendingPathComponent("press.wav")
        let release = root.appendingPathComponent("release.wav")
        let splitTime = analysis.duration / 2
        let exported = try await splitter.exportSplit(
            sourceURL: source,
            splitTime: splitTime,
            releaseEndTime: analysis.duration,
            pressDestination: press,
            releaseDestination: release
        )
        try results.check(exported.pressFrameCount > 0, "press export should not be empty")
        try results.check(exported.releaseFrameCount > 0, "release export should not be empty")
        let pressInfo = try AudioImportService.validateNormalizedAudio(at: press)
        let releaseInfo = try AudioImportService.validateNormalizedAudio(at: release)
        try results.check(pressInfo.sampleRate == 48_000, "press export should be normalized")
        try results.check(releaseInfo.sampleRate == 48_000, "release export should be normalized")

        _ = try await splitter.exportSplit(
            sourceURL: source,
            splitTime: splitTime,
            releaseEndTime: analysis.duration,
            pressDestination: press,
            releaseDestination: release,
            overwriteExisting: true
        )
        try results.check(
            fileManager.fileExists(atPath: press.path) && fileManager.fileExists(atPath: release.path),
            "pair overwrite should leave both outputs installed"
        )

        var constrainedConfiguration = AudioSplitConfiguration()
        constrainedConfiguration.maximumDecodedBytes = 1_024
        let constrained = AudioSplitService(configuration: constrainedConfiguration)
        do {
            _ = try await constrained.analyze(sourceURL: source)
            throw HarnessFailure.assertion("oversized decoded split input should be rejected")
        } catch let error as AudioSplitError {
            guard case .decodedAudioIsTooLarge = error else {
                throw HarnessFailure.assertion("wrong split memory-limit error: \(error)")
            }
            try results.check(true, "split decoded PCM limit should reject oversized input")
        }
    }

    private static func testEngineLoadFailureContract(_ results: inout HarnessResults) throws {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let engineURL = projectRoot.appendingPathComponent(
            "SimuBoardMac/SimuBoardMac/Services/KeyboardAudioEngine.swift"
        )
        let appModelURL = projectRoot.appendingPathComponent(
            "SimuBoardMac/SimuBoardMac/Services/AppModel.swift"
        )
        let engineSource = try String(contentsOf: engineURL, encoding: .utf8)
        let appModelSource = try String(contentsOf: appModelURL, encoding: .utf8)

        try results.check(
            engineSource.contains("func load(document: SoundPackDocument) -> Bool"),
            "custom engine loading must report success/failure"
        )
        guard let loadStart = engineSource.range(of: "func load(document: SoundPackDocument) -> Bool")?.lowerBound,
              let playStart = engineSource.range(of: "    func play(", range: loadStart..<engineSource.endIndex)?.lowerBound else {
            throw HarnessFailure.assertion("could not isolate custom load implementation")
        }
        let customLoadSource = engineSource[loadStart..<playStart]
        let failurePosition = customLoadSource.range(of: "return false")?.lowerBound
        let commitPosition = customLoadSource.range(of: "loadedSelectionID = document.id")?.lowerBound
        try results.check(
            failurePosition != nil && commitPosition != nil && failurePosition! < commitPosition!,
            "custom load should validate resources before committing selection state"
        )
        try results.check(
            appModelSource.contains("if audioEngine.load(document: document)")
                && appModelSource.contains("audioEngine.load(profile: fallback)"),
            "AppModel must detect custom-load failure and perform an explicit fallback"
        )
        try results.check(
            appModelSource.contains("DIY 音色载入失败，已回退到"),
            "fallback should remain visible to the user instead of silently playing the prior pack"
        )
        try results.check(
            appModelSource.contains("guard audioEngine.load(pointerProfile: profile) else")
                && appModelSource.contains("rollBackPointerSelection(to: fallback)"),
            "pointer profile loading must roll back the UI selection after resource failure"
        )
        guard let keyboardHandlerStart = appModelSource.range(
            of: "private func handle(_ event: KeyboardEvent)"
        )?.lowerBound,
        let pointerHandlerStart = appModelSource.range(
            of: "private func handle(_ event: PointerEvent)"
        )?.lowerBound,
        let pointerHandlerEnd = appModelSource.range(
            of: "private func loadPointerSoundProfile",
            range: pointerHandlerStart..<appModelSource.endIndex
        )?.lowerBound else {
            throw HarnessFailure.assertion("could not isolate keyboard and pointer audio routing")
        }
        let keyboardHandlerSource = appModelSource[keyboardHandlerStart..<pointerHandlerStart]
        let pointerHandlerSource = appModelSource[pointerHandlerStart..<pointerHandlerEnd]
        try results.check(
            keyboardHandlerSource.contains("volume: settings.volume")
                && !keyboardHandlerSource.contains("settings.pointerVolume"),
            "keyboard events must use only the keyboard volume"
        )
        try results.check(
            pointerHandlerSource.contains("volume: settings.pointerVolume")
                && !pointerHandlerSource.contains("volume: settings.volume"),
            "pointer events must use only the pointer volume"
        )
    }

    @MainActor
    private static func testUpdateCachingAndThrottling(_ results: inout HarnessResults) async throws {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appSource = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "SimuBoardMac/SimuBoardMac/SimuBoardApp.swift"
            ),
            encoding: .utf8
        )
        try results.check(
            appSource.contains("model.updates.scheduleAutomaticCheck(after: 0)"),
            "opening the menu must schedule an automatic update check"
        )

        let release = try ReleaseSummary(
            tagName: "v0.4.1",
            releaseURL: URL(string: "https://github.com/7b7b7b/simuboard/releases/tag/v0.4.1")!,
            publishedAt: nil
        )
        let rateLimit = GitHubRateLimit(remaining: 59, resetAt: nil)
        let modified = GitHubReleaseFetchResult.modified(
            release: release,
            etag: "etag-041",
            rateLimit: rateLimit
        )
        let notModified = GitHubReleaseFetchResult.notModified(
            etag: "etag-041",
            rateLimit: rateLimit
        )
        let recorder = FetchRecorder([.success(modified), .success(notModified), .success(notModified)])
        let client = GitHubReleaseClient { etag in try await recorder.fetch(etag: etag) }
        let suiteName = "SimuBoard.DIYCoreHarness.Updates.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw HarnessFailure.assertion("could not create isolated UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let clock = LockedClock(Date(timeIntervalSince1970: 1_800_000_000))
        let installed = SemanticVersion(major: 0, minor: 4, patch: 0)
        let controller = UpdateController(
            client: client,
            installedVersion: installed,
            defaults: defaults,
            now: clock.now
        )
        await controller.check(trigger: .automatic)
        let disabledAutomaticCallCount = await recorder.callCount
        try results.check(
            disabledAutomaticCallCount == 0,
            "menu-open automatic checks must remain disabled until the user opts in"
        )
        controller.enableAutomaticChecks(checkImmediately: false)
        await controller.check(trigger: .manual)
        let firstManualCallCount = await recorder.callCount
        try results.check(firstManualCallCount == 1, "first manual check should fetch")
        try results.check(controller.availableRelease?.version == SemanticVersion("0.4.1"), "newer release should surface")

        clock.advance(5)
        await controller.check(trigger: .manual)
        let spacedManualCallCount = await recorder.callCount
        try results.check(spacedManualCallCount == 1, "manual checks within 65 seconds should be suppressed")
        guard case let .failed(.requestedTooSoon(manualRetryAt), cached) = controller.state else {
            throw HarnessFailure.assertion("a throttled manual check should explain when retry is allowed")
        }
        try results.check(
            manualRetryAt == clock.now().addingTimeInterval(60)
                && cached?.result == .updateAvailable(release),
            "manual spacing feedback should retain the cached update and expose the exact retry time"
        )

        clock.advance(61)
        await controller.check(trigger: .manual)
        let resumedManualCallCount = await recorder.callCount
        try results.check(resumedManualCallCount == 2, "manual check should resume after spacing window")
        let firstControllerETags = await recorder.etags
        try results.check(firstControllerETags.last! == "etag-041", "subsequent fetch should send cached ETag")

        let relaunchedRecorder = FetchRecorder([.success(notModified)])
        let relaunchedClient = GitHubReleaseClient { etag in try await relaunchedRecorder.fetch(etag: etag) }
        let relaunched = UpdateController(
            client: relaunchedClient,
            installedVersion: installed,
            defaults: defaults,
            now: clock.now
        )
        try results.check(relaunched.availableRelease?.version == SemanticVersion("0.4.1"), "cached result should survive relaunch")
        await relaunched.check(trigger: .automatic)
        let cachedAutomaticCallCount = await relaunchedRecorder.callCount
        try results.check(
            cachedAutomaticCallCount == 0,
            "reopening the menu within five minutes should reuse the cached result"
        )

        clock.advance(5 * 60 + 1)
        await relaunched.check(trigger: .automatic)
        let expiredAutomaticCallCount = await relaunchedRecorder.callCount
        try results.check(
            expiredAutomaticCallCount == 1,
            "reopening the menu should refresh after the five-minute spacing window"
        )
        let relaunchedETags = await relaunchedRecorder.etags
        try results.check(relaunchedETags == ["etag-041"], "relaunch should retain ETag cache")

        let failureSuite = "SimuBoard.DIYCoreHarness.UpdateFailures.\(UUID().uuidString)"
        guard let failureDefaults = UserDefaults(suiteName: failureSuite) else {
            throw HarnessFailure.assertion("could not create failure UserDefaults")
        }
        defer { failureDefaults.removePersistentDomain(forName: failureSuite) }
        let failureClock = LockedClock(Date(timeIntervalSince1970: 1_900_000_000))
        let failureRecorder = FetchRecorder([
            .failure(URLError(.notConnectedToInternet)),
            .failure(URLError(.notConnectedToInternet)),
        ])
        let failureClient = GitHubReleaseClient { etag in try await failureRecorder.fetch(etag: etag) }
        let failures = UpdateController(
            client: failureClient,
            installedVersion: installed,
            defaults: failureDefaults,
            now: failureClock.now
        )
        failures.enableAutomaticChecks(checkImmediately: false)
        await failures.check(trigger: .automatic)
        let firstFailureCallCount = await failureRecorder.callCount
        try results.check(firstFailureCallCount == 1, "first automatic failure should fetch once")
        failureClock.advance(4 * 60)
        await failures.check(trigger: .automatic)
        let cooldownCallCount = await failureRecorder.callCount
        try results.check(
            cooldownCallCount == 1,
            "failed menu-open checks should still respect the five-minute spacing window"
        )
        failureClock.advance(61)
        await failures.check(trigger: .automatic)
        let expiredCooldownCallCount = await failureRecorder.callCount
        try results.check(
            expiredCooldownCallCount == 2,
            "a failed menu-open check should be retryable after five minutes"
        )

        let limitSuite = "SimuBoard.DIYCoreHarness.UpdateRateLimit.\(UUID().uuidString)"
        guard let limitDefaults = UserDefaults(suiteName: limitSuite) else {
            throw HarnessFailure.assertion("could not create rate-limit UserDefaults")
        }
        defer { limitDefaults.removePersistentDomain(forName: limitSuite) }
        let limitClock = LockedClock(Date(timeIntervalSince1970: 2_000_000_000))
        let retryAt = limitClock.now().addingTimeInterval(120)
        let limitRecorder = FetchRecorder([
            .failure(GitHubReleaseClientError.rateLimited(retryAt: retryAt)),
            .success(modified),
        ])
        let limitClient = GitHubReleaseClient { etag in try await limitRecorder.fetch(etag: etag) }
        let limited = UpdateController(
            client: limitClient,
            installedVersion: installed,
            defaults: limitDefaults,
            now: limitClock.now
        )
        await limited.check(trigger: .manual)
        limitClock.advance(60)
        await limited.check(trigger: .manual)
        let blockedRateLimitCalls = await limitRecorder.callCount
        try results.check(blockedRateLimitCalls == 1, "server retry deadline should block both manual and automatic requests")
        limitClock.advance(61)
        await limited.check(trigger: .manual)
        let resumedRateLimitCalls = await limitRecorder.callCount
        try results.check(resumedRateLimitCalls == 2, "requesting should resume after server retry deadline")

        let exhaustedSuite = "SimuBoard.DIYCoreHarness.UpdateExhausted.\(UUID().uuidString)"
        guard let exhaustedDefaults = UserDefaults(suiteName: exhaustedSuite) else {
            throw HarnessFailure.assertion("could not create exhausted-rate UserDefaults")
        }
        defer { exhaustedDefaults.removePersistentDomain(forName: exhaustedSuite) }
        let exhaustedClock = LockedClock(Date(timeIntervalSince1970: 2_100_000_000))
        let exhaustedReset = exhaustedClock.now().addingTimeInterval(120)
        let exhaustedRecorder = FetchRecorder([
            .success(
                .modified(
                    release: release,
                    etag: "etag-exhausted",
                    rateLimit: GitHubRateLimit(remaining: 0, resetAt: exhaustedReset)
                )
            ),
            .success(notModified),
        ])
        let exhaustedClient = GitHubReleaseClient {
            etag in try await exhaustedRecorder.fetch(etag: etag)
        }
        let exhausted = UpdateController(
            client: exhaustedClient,
            installedVersion: installed,
            defaults: exhaustedDefaults,
            now: exhaustedClock.now
        )
        await exhausted.check(trigger: .manual)
        exhaustedClock.advance(66)
        await exhausted.check(trigger: .manual)
        let proactivelyBlockedCalls = await exhaustedRecorder.callCount
        try results.check(
            proactivelyBlockedCalls == 1,
            "a successful response with zero remaining requests should honor its reset time"
        )
        exhaustedClock.advance(55)
        await exhausted.check(trigger: .manual)
        let proactivelyResumedCalls = await exhaustedRecorder.callCount
        try results.check(
            proactivelyResumedCalls == 2,
            "manual requests should resume after an exhausted successful response resets"
        )
    }

    private static func soundAssetID(_ character: Character) -> SoundPackAssetID {
        SoundPackAssetID(String(repeating: String(character), count: 64))
    }

    private static func fakeAsset(id: SoundPackAssetID) -> SoundPackAudioAsset {
        SoundPackAudioAsset(
            id: id,
            relativePath: "assets/\(id.rawValue).wav",
            sha256: id.rawValue,
            durationSeconds: 0.1,
            byteCount: 9_644
        )
    }

    private static func makeStereoFixture(
        at url: URL,
        sampleRate: Double,
        duration: Double
    ) throws {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else {
            throw HarnessFailure.assertion("could not make source audio format")
        }
        let frameCount = AVAudioFrameCount((sampleRate * duration).rounded())
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            throw HarnessFailure.assertion("could not make source audio buffer")
        }
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            let value = Float(sin(2 * Double.pi * 440 * Double(frame) / sampleRate) * 0.25)
            channels[0][frame] = value
            channels[1][frame] = -value * 0.75
        }
        var outputSettings = format.settings
        outputSettings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(
            forWriting: url,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }

    private static func makeSleepingExecutable(at url: URL, pidFileURL: URL) throws {
        let quotedPIDPath = pidFileURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        #!/bin/sh
        printf '%s' "$$" > '\(quotedPIDPath)'
        exec /bin/sleep 30
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func readProcessIdentifier(at url: URL) throws -> pid_t {
        let contents = try String(contentsOf: url, encoding: .utf8)
        guard let identifier = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)),
              identifier > 0 else {
            throw HarnessFailure.assertion("invalid process identifier fixture")
        }
        return identifier
    }

    private static func processExists(_ identifier: pid_t) -> Bool {
        Darwin.kill(identifier, 0) == 0
    }

    private static func waitForFile(at url: URL, timeoutSeconds: TimeInterval) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeoutSeconds
        while ProcessInfo.processInfo.systemUptime < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
