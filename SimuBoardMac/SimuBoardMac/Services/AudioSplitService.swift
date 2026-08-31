import AVFAudio
import Accelerate
import Foundation

/// Limits and analysis parameters for a single, complete keystroke recording.
///
/// `AudioSplitService` converts every source to 48 kHz mono before analysis, so
/// frame-based values remain deterministic across MP3, WAV, and AIFF inputs.
struct AudioSplitConfiguration: Hashable, Sendable {
    var minimumDuration: TimeInterval = 0.030
    var maximumDuration: TimeInterval = 15
    var maximumSourceBytes: Int64 = 64 * 1_024 * 1_024
    var maximumDecodedBytes: Int64 = 64 * 1_024 * 1_024
    var minimumSampleRate = 1_000.0
    var maximumSampleRate = 384_000.0
    var maximumChannelCount: AVAudioChannelCount = 32
    var minimumSegmentDuration: TimeInterval = 0.012
    var analysisWindowDuration: TimeInterval = 0.004
    var analysisHopDuration: TimeInterval = 0.001
    var minimumReleaseDelay: TimeInterval = 0.055
    var waveformPointCount = 256
    var envelopePointCount = 512
}

enum AudioSplitError: Error, LocalizedError, Sendable {
    case invalidConfiguration(String)
    case sourceNotFound
    case sourceIsNotARegularFile
    case sourceIsEmpty
    case sourceIsTooLarge(actualBytes: Int64, maximumBytes: Int64)
    case decodedAudioIsTooLarge(estimatedBytes: Int64, maximumBytes: Int64)
    case unsupportedSourceFormat
    case durationOutOfRange(actual: TimeInterval, minimum: TimeInterval, maximum: TimeInterval)
    case decodedAudioIsEmpty
    case decodingFailed(String)
    case conversionFailed
    case invalidSplitTime(actual: TimeInterval, duration: TimeInterval)
    case invalidReleaseEndTime(actual: TimeInterval, splitTime: TimeInterval, duration: TimeInterval)
    case destinationsMustBeDifferent
    case destinationMatchesSource
    case destinationAlreadyExists(URL)
    case cannotCreateOutputBuffer
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            L10n.format("音频拆分配置无效：%@", message)
        case .sourceNotFound:
            L10n.tr("找不到音频文件。")
        case .sourceIsNotARegularFile:
            L10n.tr("选择的项目不是普通音频文件。")
        case .sourceIsEmpty:
            L10n.tr("音频文件为空。")
        case let .sourceIsTooLarge(actualBytes, maximumBytes):
            L10n.format(
                "音频文件过大（%@ 字节，上限 %@ 字节）。",
                "\(actualBytes)",
                "\(maximumBytes)"
            )
        case let .decodedAudioIsTooLarge(estimatedBytes, maximumBytes):
            L10n.format(
                "音频解码后过大（预计 %@ 字节，上限 %@ 字节）。",
                "\(estimatedBytes)",
                "\(maximumBytes)"
            )
        case .unsupportedSourceFormat:
            L10n.tr("音频格式或声道布局不受支持。")
        case let .durationOutOfRange(actual, minimum, maximum):
            L10n.format(
                "音频时长 %@ 秒不在允许范围 %@–%@ 秒内。",
                actual.formatted(
                    .number.precision(.fractionLength(3)).locale(L10n.locale)
                ),
                "\(minimum)",
                "\(maximum)"
            )
        case .decodedAudioIsEmpty:
            L10n.tr("音频解码后没有可分析的采样。")
        case let .decodingFailed(message):
            L10n.format("无法读取音频：%@", message)
        case .conversionFailed:
            L10n.tr("无法将音频转换为 48 kHz 单声道。")
        case let .invalidSplitTime(actual, duration):
            L10n.format(
                "拆分时间 %@ 秒超出有效范围（音频总长 %@ 秒）。",
                "\(actual)",
                "\(duration)"
            )
        case let .invalidReleaseEndTime(actual, splitTime, duration):
            L10n.format(
                "回弹结束时间 %@ 秒无效；它必须晚于 %@ 秒且不超过 %@ 秒。",
                "\(actual)",
                "\(splitTime)",
                "\(duration)"
            )
        case .destinationsMustBeDifferent:
            L10n.tr("按下与回弹音频必须导出到不同文件。")
        case .destinationMatchesSource:
            L10n.tr("导出位置不能覆盖原始音频。")
        case let .destinationAlreadyExists(url):
            L10n.format("目标文件已存在：%@", url.lastPathComponent)
        case .cannotCreateOutputBuffer:
            L10n.tr("无法创建导出音频缓冲区。")
        case let .exportFailed(message):
            L10n.format("导出音频失败：%@", message)
        }
    }
}

enum AudioSplitAnalysisWarning: String, Hashable, Sendable {
    case lowConfidence
    case fallbackValleyUsed
    case possibleAdditionalKeystroke
    case sourceMayBeClipped
}

struct AudioWaveformPoint: Hashable, Sendable {
    let time: TimeInterval
    let minimum: Float
    let maximum: Float
    let rootMeanSquare: Float
}

struct AudioEnergyEnvelopePoint: Hashable, Sendable {
    let time: TimeInterval
    let rootMeanSquare: Float
    let peak: Float
    let rootMeanSquareDBFS: Float
    let peakDBFS: Float
}

struct AudioSplitSegmentPreview: Hashable, Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let duration: TimeInterval
    let transientOffset: TimeInterval
    let peak: Float
    let rootMeanSquare: Float
    let peakDBFS: Float
    let rootMeanSquareDBFS: Float
}

struct AudioSplitSuggestion: Hashable, Sendable {
    let splitTime: TimeInterval
    let pressTransientTime: TimeInterval
    let valleyTime: TimeInterval
    let releaseTransientTime: TimeInterval
    let suggestedReleaseEndTime: TimeInterval?
    let confidence: Float
    let usedFallback: Bool
}

struct AudioSplitAnalysis: Hashable, Sendable {
    let sourceURL: URL
    let sourceByteCount: Int64
    let duration: TimeInterval
    let sampleRate: Double
    let frameCount: Int
    let suggestion: AudioSplitSuggestion
    let pressPreview: AudioSplitSegmentPreview
    let releasePreview: AudioSplitSegmentPreview
    let waveform: [AudioWaveformPoint]
    let energyEnvelope: [AudioEnergyEnvelopePoint]
    let warnings: Set<AudioSplitAnalysisWarning>
}

struct AudioSplitExportResult: Hashable, Sendable {
    let pressURL: URL
    let releaseURL: URL
    let splitTime: TimeInterval
    let releaseEndTime: TimeInterval
    let pressFrameCount: Int
    let releaseFrameCount: Int
    let sampleRate: Double
}

/// Performs synchronous AVFoundation and Accelerate work on its own actor,
/// never on the main actor. Calls are serialized so AVAudioFile and temporary
/// export state never cross concurrency domains.
actor AudioSplitService {
    static let outputSampleRate = 48_000.0

    private struct DecodedAudio {
        let samples: [Float]
        let sourceByteCount: Int64

        var duration: TimeInterval {
            Double(samples.count) / AudioSplitService.outputSampleRate
        }
    }

    private struct AnalysisFrame {
        let time: TimeInterval
        let rootMeanSquare: Float
        let peak: Float

        var rootMeanSquareDBFS: Float {
            AudioSplitService.decibels(rootMeanSquare)
        }

        var peakDBFS: Float {
            AudioSplitService.decibels(peak)
        }
    }

    private struct ReleaseCandidate {
        let onsetIndex: Int
        let valleyIndex: Int
        let peakIndex: Int
        let score: Float
        let riseDB: Float
        let prominenceDB: Float
    }

    private struct Detection {
        let pressPeakIndex: Int
        let releaseCandidate: ReleaseCandidate
        let releaseEndIndex: Int?
        let confidence: Float
        let usedFallback: Bool
        let possibleAdditionalKeystroke: Bool
    }

    private let configuration: AudioSplitConfiguration

    init(configuration: AudioSplitConfiguration = AudioSplitConfiguration()) {
        self.configuration = configuration
    }

    func analyze(sourceURL: URL) async throws -> AudioSplitAnalysis {
        try validateConfiguration()
        try Task.checkCancellation()

        let audio = try decode(sourceURL: sourceURL)
        try Task.checkCancellation()

        let frames = try makeAnalysisFrames(samples: audio.samples)
        let detection = try detectSplit(in: frames, duration: audio.duration)
        let waveform = try makeWaveform(samples: audio.samples)
        let energyEnvelope = downsampleEnvelope(frames)
        try Task.checkCancellation()

        let splitTime = clampSplitTime(
            frames[detection.releaseCandidate.onsetIndex].time,
            duration: audio.duration
        )
        let releaseEndTime = detection.releaseEndIndex.map { frames[$0].time }
        let previewEndTime = releaseEndTime ?? audio.duration
        let pressTransientTime = frames[detection.pressPeakIndex].time
        let valleyTime = frames[detection.releaseCandidate.valleyIndex].time
        let releaseTransientTime = frames[detection.releaseCandidate.peakIndex].time

        let pressPreview = segmentPreview(
            samples: audio.samples,
            startTime: 0,
            endTime: splitTime,
            transientTime: pressTransientTime
        )
        let releasePreview = segmentPreview(
            samples: audio.samples,
            startTime: splitTime,
            endTime: previewEndTime,
            transientTime: releaseTransientTime
        )

        var warnings: Set<AudioSplitAnalysisWarning> = []
        if detection.confidence < 0.55 { warnings.insert(.lowConfidence) }
        if detection.usedFallback { warnings.insert(.fallbackValleyUsed) }
        if detection.possibleAdditionalKeystroke {
            warnings.insert(.possibleAdditionalKeystroke)
        }
        if waveform.contains(where: { max(abs($0.minimum), abs($0.maximum)) >= 0.999 }) {
            warnings.insert(.sourceMayBeClipped)
        }

        return AudioSplitAnalysis(
            sourceURL: sourceURL,
            sourceByteCount: audio.sourceByteCount,
            duration: audio.duration,
            sampleRate: Self.outputSampleRate,
            frameCount: audio.samples.count,
            suggestion: AudioSplitSuggestion(
                splitTime: splitTime,
                pressTransientTime: pressTransientTime,
                valleyTime: valleyTime,
                releaseTransientTime: releaseTransientTime,
                suggestedReleaseEndTime: releaseEndTime,
                confidence: detection.confidence,
                usedFallback: detection.usedFallback
            ),
            pressPreview: pressPreview,
            releasePreview: releasePreview,
            waveform: waveform,
            energyEnvelope: energyEnvelope,
            warnings: warnings
        )
    }

    /// Exports a manual or suggested split as two 48 kHz mono, 16-bit PCM WAVs.
    /// Pass `releaseEndTime` to omit a detected subsequent keystroke.
    func exportSplit(
        sourceURL: URL,
        splitTime: TimeInterval,
        releaseEndTime: TimeInterval? = nil,
        pressDestination: URL,
        releaseDestination: URL,
        overwriteExisting: Bool = false
    ) async throws -> AudioSplitExportResult {
        try validateConfiguration()
        try Task.checkCancellation()
        try validateDestinations(
            sourceURL: sourceURL,
            pressDestination: pressDestination,
            releaseDestination: releaseDestination,
            overwriteExisting: overwriteExisting
        )

        let audio = try decode(sourceURL: sourceURL)
        let duration = audio.duration
        guard splitTime.isFinite,
              splitTime >= configuration.minimumSegmentDuration,
              splitTime <= duration - configuration.minimumSegmentDuration else {
            throw AudioSplitError.invalidSplitTime(actual: splitTime, duration: duration)
        }

        let resolvedReleaseEnd = releaseEndTime ?? duration
        guard resolvedReleaseEnd.isFinite,
              resolvedReleaseEnd > splitTime + configuration.minimumSegmentDuration,
              resolvedReleaseEnd <= duration else {
            throw AudioSplitError.invalidReleaseEndTime(
                actual: resolvedReleaseEnd,
                splitTime: splitTime,
                duration: duration
            )
        }

        let splitFrame = frame(at: splitTime, frameCount: audio.samples.count)
        let releaseEndFrame = frame(
            at: resolvedReleaseEnd,
            frameCount: audio.samples.count
        )
        var pressSamples = Array(audio.samples[..<splitFrame])
        var releaseSamples = Array(audio.samples[splitFrame..<releaseEndFrame])
        applyLinearFade(to: &pressSamples, fadeIn: 0, fadeOut: 0.004)
        applyLinearFade(to: &releaseSamples, fadeIn: 0.002, fadeOut: 0.004)
        try Task.checkCancellation()

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: pressDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: releaseDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let temporaryPressURL = temporaryOutputURL(for: pressDestination)
        let temporaryReleaseURL = temporaryOutputURL(for: releaseDestination)
        defer {
            try? fileManager.removeItem(at: temporaryPressURL)
            try? fileManager.removeItem(at: temporaryReleaseURL)
        }

        do {
            try writePCM16Wave(samples: pressSamples, to: temporaryPressURL)
            try Task.checkCancellation()
            try writePCM16Wave(samples: releaseSamples, to: temporaryReleaseURL)
            try Task.checkCancellation()
            try installPair(
                temporaryPressURL: temporaryPressURL,
                pressDestination: pressDestination,
                temporaryReleaseURL: temporaryReleaseURL,
                releaseDestination: releaseDestination,
                overwriteExisting: overwriteExisting
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AudioSplitError {
            throw error
        } catch {
            throw AudioSplitError.exportFailed(error.localizedDescription)
        }

        return AudioSplitExportResult(
            pressURL: pressDestination,
            releaseURL: releaseDestination,
            splitTime: splitTime,
            releaseEndTime: resolvedReleaseEnd,
            pressFrameCount: pressSamples.count,
            releaseFrameCount: releaseSamples.count,
            sampleRate: Self.outputSampleRate
        )
    }

    private func validateConfiguration() throws {
        guard configuration.minimumDuration.isFinite,
              configuration.maximumDuration.isFinite,
              configuration.minimumSegmentDuration.isFinite,
              configuration.analysisWindowDuration.isFinite,
              configuration.analysisHopDuration.isFinite,
              configuration.minimumReleaseDelay.isFinite,
              configuration.minimumDuration > 0,
              configuration.maximumDuration > configuration.minimumDuration,
              configuration.minimumSegmentDuration > 0,
              configuration.minimumSegmentDuration * 2 < configuration.minimumDuration,
              configuration.analysisWindowDuration > 0,
              configuration.analysisHopDuration > 0,
              configuration.minimumReleaseDelay > configuration.analysisHopDuration,
              configuration.maximumSourceBytes > 0,
              configuration.maximumDecodedBytes > 0,
              configuration.minimumSampleRate.isFinite,
              configuration.minimumSampleRate > 0,
              configuration.minimumSampleRate <= Self.outputSampleRate,
              configuration.maximumSampleRate.isFinite,
              configuration.maximumSampleRate >= Self.outputSampleRate,
              configuration.maximumChannelCount > 0,
              configuration.waveformPointCount > 0,
              configuration.envelopePointCount > 0 else {
            throw AudioSplitError.invalidConfiguration(
                L10n.tr("参数必须为有限正数，且最短片段不能超过最短音频的一半。")
            )
        }
    }

    private func estimatedDecodedByteCount(
        frameCount: AVAudioFramePosition,
        format: AVAudioFormat
    ) -> Int64? {
        guard frameCount > 0 else { return nil }
        let bytesPerFrame = Int64(format.streamDescription.pointee.mBytesPerFrame)
        let bufferCount = format.isInterleaved ? 1 : Int64(format.channelCount)
        guard bytesPerFrame > 0, bufferCount > 0 else { return nil }

        let (bytesPerBuffer, frameOverflow) = frameCount.multipliedReportingOverflow(
            by: bytesPerFrame
        )
        guard !frameOverflow else { return nil }
        let (totalBytes, channelOverflow) = bytesPerBuffer.multipliedReportingOverflow(
            by: bufferCount
        )
        return channelOverflow ? nil : totalBytes
    }

    private func decode(sourceURL: URL) throws -> DecodedAudio {
        let didStartSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AudioSplitError.sourceNotFound
        }

        let resourceValues = try sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey]
        )
        guard resourceValues.isRegularFile == true else {
            throw AudioSplitError.sourceIsNotARegularFile
        }
        let byteCount = Int64(resourceValues.fileSize ?? 0)
        guard byteCount > 0 else { throw AudioSplitError.sourceIsEmpty }
        guard byteCount <= configuration.maximumSourceBytes else {
            throw AudioSplitError.sourceIsTooLarge(
                actualBytes: byteCount,
                maximumBytes: configuration.maximumSourceBytes
            )
        }

        do {
            try Task.checkCancellation()
            let file = try AVAudioFile(forReading: sourceURL)
            let sourceFormat = file.processingFormat
            guard file.length > 0,
                  sourceFormat.sampleRate.isFinite,
                  sourceFormat.sampleRate >= configuration.minimumSampleRate,
                  sourceFormat.sampleRate <= configuration.maximumSampleRate,
                  sourceFormat.channelCount > 0,
                  sourceFormat.channelCount <= configuration.maximumChannelCount else {
                throw AudioSplitError.unsupportedSourceFormat
            }

            let sourceDuration = Double(file.length) / sourceFormat.sampleRate
            guard sourceDuration >= configuration.minimumDuration,
                  sourceDuration <= configuration.maximumDuration else {
                throw AudioSplitError.durationOutOfRange(
                    actual: sourceDuration,
                    minimum: configuration.minimumDuration,
                    maximum: configuration.maximumDuration
                )
            }
            guard file.length <= AVAudioFramePosition(AVAudioFrameCount.max) else {
                throw AudioSplitError.decodedAudioIsTooLarge(
                    estimatedBytes: Int64.max,
                    maximumBytes: configuration.maximumDecodedBytes
                )
            }
            let estimatedSourceBytes = estimatedDecodedByteCount(
                frameCount: file.length,
                format: sourceFormat
            ) ?? Int64.max
            guard estimatedSourceBytes <= configuration.maximumDecodedBytes else {
                throw AudioSplitError.decodedAudioIsTooLarge(
                    estimatedBytes: estimatedSourceBytes,
                    maximumBytes: configuration.maximumDecodedBytes
                )
            }

            guard let sourceBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else {
                throw AudioSplitError.decodingFailed(L10n.tr("无法分配输入缓冲区。"))
            }
            try file.read(into: sourceBuffer)
            try Task.checkCancellation()
            guard sourceBuffer.frameLength > 0 else {
                throw AudioSplitError.decodedAudioIsEmpty
            }

            let outputBuffer = try convertToAnalysisFormat(sourceBuffer)
            guard outputBuffer.frameLength > 0,
                  let channel = outputBuffer.floatChannelData?[0] else {
                throw AudioSplitError.decodedAudioIsEmpty
            }
            let samples = Array(
                UnsafeBufferPointer(
                    start: channel,
                    count: Int(outputBuffer.frameLength)
                )
            )
            guard samples.contains(where: { $0.isFinite && abs($0) > 1e-7 }) else {
                throw AudioSplitError.decodedAudioIsEmpty
            }
            return DecodedAudio(samples: samples, sourceByteCount: byteCount)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AudioSplitError {
            throw error
        } catch {
            throw AudioSplitError.decodingFailed(error.localizedDescription)
        }
    }

    private func convertToAnalysisFormat(_ source: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.outputSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioSplitError.conversionFailed
        }

        if source.format == targetFormat { return source }
        guard let converter = AVAudioConverter(from: source.format, to: targetFormat) else {
            throw AudioSplitError.conversionFailed
        }

        let ratio = targetFormat.sampleRate / source.format.sampleRate
        let estimatedFrames = ceil(Double(source.frameLength) * ratio)
        guard estimatedFrames.isFinite,
              estimatedFrames > 0,
              estimatedFrames <= Double(AVAudioFrameCount.max - 64),
              estimatedFrames + 64
                <= Double(configuration.maximumDecodedBytes / Int64(MemoryLayout<Float>.size)) else {
            throw AudioSplitError.conversionFailed
        }
        guard let output = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(estimatedFrames) + 64
        ) else {
            throw AudioSplitError.conversionFailed
        }

        var providedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if providedInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            providedInput = true
            inputStatus.pointee = .haveData
            return source
        }
        guard conversionError == nil, output.frameLength > 0 else {
            throw AudioSplitError.conversionFailed
        }
        switch status {
        case .haveData, .endOfStream:
            return output
        case .error, .inputRanDry:
            throw AudioSplitError.conversionFailed
        @unknown default:
            throw AudioSplitError.conversionFailed
        }
    }

    private func makeAnalysisFrames(samples: [Float]) throws -> [AnalysisFrame] {
        let windowSize = max(
            16,
            Int((configuration.analysisWindowDuration * Self.outputSampleRate).rounded())
        )
        let hopSize = max(
            1,
            Int((configuration.analysisHopDuration * Self.outputSampleRate).rounded())
        )
        var result: [AnalysisFrame] = []
        result.reserveCapacity((samples.count + hopSize - 1) / hopSize)

        try samples.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw AudioSplitError.decodedAudioIsEmpty
            }
            var frameNumber = 0
            for start in stride(from: 0, to: samples.count, by: hopSize) {
                if frameNumber.isMultiple(of: 128) { try Task.checkCancellation() }
                let count = min(windowSize, samples.count - start)
                var rms: Float = 0
                var peak: Float = 0
                vDSP_rmsqv(
                    baseAddress.advanced(by: start),
                    1,
                    &rms,
                    vDSP_Length(count)
                )
                vDSP_maxmgv(
                    baseAddress.advanced(by: start),
                    1,
                    &peak,
                    vDSP_Length(count)
                )
                let centerFrame = Double(start) + Double(count) / 2
                result.append(
                    AnalysisFrame(
                        time: centerFrame / Self.outputSampleRate,
                        rootMeanSquare: rms,
                        peak: peak
                    )
                )
                frameNumber += 1
            }
        }
        guard result.count >= 3 else { throw AudioSplitError.decodedAudioIsEmpty }
        return result
    }

    private func detectSplit(in frames: [AnalysisFrame], duration: TimeInterval) throws -> Detection {
        let rmsLevels = frames.map(\.rootMeanSquareDBFS)
        let globalPeak = rmsLevels.max() ?? -120
        let noiseFloor = percentile(rmsLevels, fraction: 0.20)
        let activeThreshold = max(noiseFloor + 10, globalPeak - 28, -60)

        let firstActiveIndex = rmsLevels.indices.first { index in
            let lookAheadEnd = min(frames.count, index + frameCount(for: 0.008))
            return rmsLevels[index..<lookAheadEnd].max() ?? -120 >= activeThreshold
        } ?? rmsLevels.indices.max(by: { rmsLevels[$0] < rmsLevels[$1] }) ?? 0

        let pressSearchEnd = min(
            frames.count,
            firstActiveIndex + frameCount(for: 0.055)
        )
        let pressPeakIndex = maximumIndex(
            in: rmsLevels,
            range: firstActiveIndex..<max(firstActiveIndex + 1, pressSearchEnd)
        )
        let releaseSearchStart = min(
            frames.count - 2,
            max(
                firstActiveIndex + frameCount(for: configuration.minimumReleaseDelay),
                pressPeakIndex + frameCount(for: 0.030)
            )
        )

        var candidates: [ReleaseCandidate] = []
        let localRadius = frameCount(for: 0.004)
        let valleyLookback = frameCount(for: 0.032)
        for peakIndex in releaseSearchStart..<(frames.count - 1) {
            if peakIndex.isMultiple(of: 128) { try Task.checkCancellation() }
            let localStart = max(releaseSearchStart, peakIndex - localRadius)
            let localEnd = min(frames.count, peakIndex + localRadius + 1)
            guard rmsLevels[peakIndex] >= (rmsLevels[localStart..<localEnd].max() ?? -120)
            else { continue }

            let valleyStart = max(pressPeakIndex + 1, peakIndex - valleyLookback)
            let valleyEnd = max(valleyStart + 1, peakIndex - frameCount(for: 0.004))
            guard valleyEnd <= peakIndex else { continue }
            let valleyIndex = minimumIndex(in: rmsLevels, range: valleyStart..<valleyEnd)
            let rise = rmsLevels[peakIndex] - rmsLevels[valleyIndex]
            let prominence = rmsLevels[peakIndex] - noiseFloor
            guard rise >= 6,
                  prominence >= 8,
                  rmsLevels[peakIndex] >= globalPeak - 30 else { continue }

            let crossingLevel = rmsLevels[valleyIndex] + min(8, max(3, rise * 0.30))
            let onsetIndex = (valleyIndex...peakIndex).first {
                rmsLevels[$0] >= crossingLevel
            } ?? valleyIndex
            let quietDuration = frames[onsetIndex].time - frames[valleyIndex].time
            let score = rise + 0.40 * prominence + Float(min(quietDuration, 0.025) * 120)
            candidates.append(
                ReleaseCandidate(
                    onsetIndex: onsetIndex,
                    valleyIndex: valleyIndex,
                    peakIndex: peakIndex,
                    score: score,
                    riseDB: rise,
                    prominenceDB: prominence
                )
            )
        }

        let selected: ReleaseCandidate
        let usedFallback: Bool
        if let bestScore = candidates.map(\.score).max(),
           let earliestStrongCandidate = candidates
            .filter({ $0.score >= bestScore * 0.50 })
            .min(by: { $0.onsetIndex < $1.onsetIndex }) {
            selected = earliestStrongCandidate
            usedFallback = false
        } else {
            let fallbackStart = max(
                releaseSearchStart,
                frameCount(for: duration * 0.30)
            )
            let fallbackEnd = min(
                frames.count - 1,
                max(fallbackStart + 1, frameCount(for: duration * 0.78))
            )
            let valleyIndex = minimumIndex(
                in: rmsLevels,
                range: fallbackStart..<fallbackEnd
            )
            let peakStart = min(frames.count - 1, valleyIndex + 1)
            let peakIndex = maximumIndex(
                in: rmsLevels,
                range: peakStart..<frames.count
            )
            selected = ReleaseCandidate(
                onsetIndex: valleyIndex,
                valleyIndex: valleyIndex,
                peakIndex: peakIndex,
                score: 0,
                riseDB: max(0, rmsLevels[peakIndex] - rmsLevels[valleyIndex]),
                prominenceDB: max(0, rmsLevels[peakIndex] - noiseFloor)
            )
            usedFallback = true
        }

        let laterCandidates = candidates.filter {
            $0.onsetIndex > selected.peakIndex + frameCount(for: configuration.minimumReleaseDelay)
                && $0.score >= selected.score * 0.72
        }
        let nextKeystrokeCandidate = laterCandidates.min(by: { $0.onsetIndex < $1.onsetIndex })
        let releaseEndIndex: Int? = nextKeystrokeCandidate.map { later in
            minimumIndex(
                in: rmsLevels,
                range: selected.peakIndex..<max(selected.peakIndex + 1, later.onsetIndex)
            )
        }

        let riseConfidence = unitInterval((selected.riseDB - 6) / 18)
        let prominenceConfidence = unitInterval((selected.prominenceDB - 8) / 24)
        let separation = frames[selected.peakIndex].time - frames[pressPeakIndex].time
        let separationConfidence = unitInterval(Float((separation - 0.030) / 0.090))
        let confidence = usedFallback
            ? 0.10
            : 0.45 * riseConfidence + 0.35 * prominenceConfidence + 0.20 * separationConfidence

        return Detection(
            pressPeakIndex: pressPeakIndex,
            releaseCandidate: selected,
            releaseEndIndex: releaseEndIndex,
            confidence: confidence,
            usedFallback: usedFallback,
            possibleAdditionalKeystroke: nextKeystrokeCandidate != nil
        )
    }

    private func makeWaveform(samples: [Float]) throws -> [AudioWaveformPoint] {
        let pointCount = min(configuration.waveformPointCount, samples.count)
        var points: [AudioWaveformPoint] = []
        points.reserveCapacity(pointCount)

        try samples.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw AudioSplitError.decodedAudioIsEmpty
            }
            for pointIndex in 0..<pointCount {
                if pointIndex.isMultiple(of: 128) { try Task.checkCancellation() }
                let start = pointIndex * samples.count / pointCount
                let end = max(start + 1, (pointIndex + 1) * samples.count / pointCount)
                let count = end - start
                var minimum: Float = 0
                var maximum: Float = 0
                var rms: Float = 0
                vDSP_minv(
                    baseAddress.advanced(by: start),
                    1,
                    &minimum,
                    vDSP_Length(count)
                )
                vDSP_maxv(
                    baseAddress.advanced(by: start),
                    1,
                    &maximum,
                    vDSP_Length(count)
                )
                vDSP_rmsqv(
                    baseAddress.advanced(by: start),
                    1,
                    &rms,
                    vDSP_Length(count)
                )
                points.append(
                    AudioWaveformPoint(
                        time: (Double(start + end) / 2) / Self.outputSampleRate,
                        minimum: minimum,
                        maximum: maximum,
                        rootMeanSquare: rms
                    )
                )
            }
        }
        return points
    }

    private func downsampleEnvelope(_ frames: [AnalysisFrame]) -> [AudioEnergyEnvelopePoint] {
        let pointCount = min(configuration.envelopePointCount, frames.count)
        return (0..<pointCount).map { pointIndex in
            let start = pointIndex * frames.count / pointCount
            let end = max(start + 1, (pointIndex + 1) * frames.count / pointCount)
            let bucket = frames[start..<end]
            let rms = bucket.map(\.rootMeanSquare).max() ?? 0
            let peak = bucket.map(\.peak).max() ?? 0
            return AudioEnergyEnvelopePoint(
                time: bucket[bucket.index(bucket.startIndex, offsetBy: bucket.count / 2)].time,
                rootMeanSquare: rms,
                peak: peak,
                rootMeanSquareDBFS: Self.decibels(rms),
                peakDBFS: Self.decibels(peak)
            )
        }
    }

    private func segmentPreview(
        samples: [Float],
        startTime: TimeInterval,
        endTime: TimeInterval,
        transientTime: TimeInterval
    ) -> AudioSplitSegmentPreview {
        let start = frame(at: startTime, frameCount: samples.count)
        let end = max(start + 1, frame(at: endTime, frameCount: samples.count))
        let safeEnd = min(end, samples.count)
        var rms: Float = 0
        var peak: Float = 0
        samples.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            vDSP_rmsqv(
                baseAddress.advanced(by: start),
                1,
                &rms,
                vDSP_Length(safeEnd - start)
            )
            vDSP_maxmgv(
                baseAddress.advanced(by: start),
                1,
                &peak,
                vDSP_Length(safeEnd - start)
            )
        }
        return AudioSplitSegmentPreview(
            startTime: startTime,
            endTime: endTime,
            duration: endTime - startTime,
            transientOffset: max(0, min(endTime - startTime, transientTime - startTime)),
            peak: peak,
            rootMeanSquare: rms,
            peakDBFS: Self.decibels(peak),
            rootMeanSquareDBFS: Self.decibels(rms)
        )
    }

    private func validateDestinations(
        sourceURL: URL,
        pressDestination: URL,
        releaseDestination: URL,
        overwriteExisting: Bool
    ) throws {
        let source = sourceURL.standardizedFileURL
        let press = pressDestination.standardizedFileURL
        let release = releaseDestination.standardizedFileURL
        guard press != release else { throw AudioSplitError.destinationsMustBeDifferent }
        guard press != source, release != source else {
            throw AudioSplitError.destinationMatchesSource
        }
        guard press.pathExtension.lowercased() == "wav",
              release.pathExtension.lowercased() == "wav" else {
            throw AudioSplitError.exportFailed(L10n.tr("目标文件扩展名必须是 .wav。"))
        }
        if !overwriteExisting {
            if FileManager.default.fileExists(atPath: press.path) {
                throw AudioSplitError.destinationAlreadyExists(press)
            }
            if FileManager.default.fileExists(atPath: release.path) {
                throw AudioSplitError.destinationAlreadyExists(release)
            }
        }
    }

    private func writePCM16Wave(samples: [Float], to url: URL) throws {
        guard !samples.isEmpty,
              samples.count <= Int(AVAudioFrameCount.max),
              let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Self.outputSampleRate,
                channels: 1,
                interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.int16ChannelData?[0] else {
            throw AudioSplitError.cannotCreateOutputBuffer
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        for index in samples.indices {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let sample = max(-1, min(0.999_969_5, samples[index]))
            channel[index] = Int16((sample * Float(Int16.max)).rounded())
        }
        let outputFile = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: false
        )
        try outputFile.write(from: buffer)
    }

    private func installPair(
        temporaryPressURL: URL,
        pressDestination: URL,
        temporaryReleaseURL: URL,
        releaseDestination: URL,
        overwriteExisting: Bool
    ) throws {
        let fileManager = FileManager.default
        var backups: [(destination: URL, backup: URL)] = []
        var installedDestinations: [URL] = []

        do {
            for destination in [pressDestination, releaseDestination]
            where fileManager.fileExists(atPath: destination.path) {
                guard overwriteExisting else {
                    throw AudioSplitError.destinationAlreadyExists(destination)
                }
                let backup = destination.deletingLastPathComponent().appendingPathComponent(
                    ".\(destination.lastPathComponent).\(UUID().uuidString).split-backup"
                )
                try fileManager.moveItem(at: destination, to: backup)
                backups.append((destination, backup))
            }

            try fileManager.moveItem(at: temporaryPressURL, to: pressDestination)
            installedDestinations.append(pressDestination)
            try fileManager.moveItem(at: temporaryReleaseURL, to: releaseDestination)
            installedDestinations.append(releaseDestination)

            for entry in backups { try? fileManager.removeItem(at: entry.backup) }
        } catch {
            var rollbackFailures: [String] = []
            for destination in installedDestinations.reversed() {
                do { try fileManager.removeItem(at: destination) }
                catch { rollbackFailures.append(error.localizedDescription) }
            }
            for entry in backups.reversed() {
                do { try fileManager.moveItem(at: entry.backup, to: entry.destination) }
                catch { rollbackFailures.append(error.localizedDescription) }
            }
            if !rollbackFailures.isEmpty {
                throw AudioSplitError.exportFailed(
                    L10n.format(
                        "导出失败，且无法完整恢复原文件：%@",
                        rollbackFailures.joined(separator: "; ")
                    )
                )
            }
            throw error
        }
    }

    private func applyLinearFade(
        to samples: inout [Float],
        fadeIn: TimeInterval,
        fadeOut: TimeInterval
    ) {
        let fadeInFrames = min(samples.count, Int((fadeIn * Self.outputSampleRate).rounded()))
        if fadeInFrames > 1 {
            for index in 0..<fadeInFrames {
                samples[index] *= Float(index) / Float(fadeInFrames - 1)
            }
        }
        let fadeOutFrames = min(samples.count, Int((fadeOut * Self.outputSampleRate).rounded()))
        if fadeOutFrames > 1 {
            let fadeStart = samples.count - fadeOutFrames
            for index in 0..<fadeOutFrames {
                samples[fadeStart + index] *= Float(fadeOutFrames - 1 - index)
                    / Float(fadeOutFrames - 1)
            }
        }
    }

    private func clampSplitTime(
        _ value: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval {
        max(
            configuration.minimumSegmentDuration,
            min(duration - configuration.minimumSegmentDuration, value)
        )
    }

    private func frame(at time: TimeInterval, frameCount: Int) -> Int {
        min(
            frameCount,
            max(0, Int((time * Self.outputSampleRate).rounded()))
        )
    }

    private func frameCount(for duration: TimeInterval) -> Int {
        max(
            1,
            Int((duration / configuration.analysisHopDuration).rounded())
        )
    }

    private func temporaryOutputURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.deletingPathExtension().lastPathComponent).\(UUID().uuidString).tmp.wav"
        )
    }

    private func maximumIndex(in values: [Float], range: Range<Int>) -> Int {
        range.max(by: { values[$0] < values[$1] }) ?? range.lowerBound
    }

    private func minimumIndex(in values: [Float], range: Range<Int>) -> Int {
        range.min(by: { values[$0] < values[$1] }) ?? range.lowerBound
    }

    private func percentile(_ values: [Float], fraction: Float) -> Float {
        guard !values.isEmpty else { return -120 }
        let sorted = values.sorted()
        let index = min(
            sorted.count - 1,
            max(0, Int((Float(sorted.count - 1) * fraction).rounded()))
        )
        return sorted[index]
    }

    private func unitInterval(_ value: Float) -> Float {
        max(0, min(1, value))
    }

    nonisolated private static func decibels(_ amplitude: Float) -> Float {
        20 * log10(max(amplitude, 1e-7))
    }
}
