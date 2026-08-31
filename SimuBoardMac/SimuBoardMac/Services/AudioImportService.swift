import AudioToolbox
import AVFAudio
import Darwin
import Foundation

struct NormalizedSoundPackAudioInfo: Hashable, Sendable {
    let durationSeconds: Double
    let byteCount: Int64
    let sampleRate: Int
    let channelCount: Int
}

struct PreparedSoundPackAudio: Identifiable, Sendable {
    let metadata: SoundPackAudioAsset
    let normalizedFileURL: URL

    var id: SoundPackAssetID { metadata.id }
}

actor AudioImportService {
    static let targetSampleRate = 48_000.0
    static let maximumDecodedPCMBytes: Int64 = 64 * 1_024 * 1_024

    private static let minimumSourceSampleRate = 1_000.0
    private static let maximumSourceSampleRate = 384_000.0
    private static let maximumSourceChannelCount = 8
    private static let defaultFFmpegTimeoutSeconds: TimeInterval = 20
    private static let ffmpegPollIntervalSeconds: TimeInterval = 0.025
    private static let ffmpegTerminationGraceSeconds: TimeInterval = 0.5
    private static let ffmpegKillGraceSeconds: TimeInterval = 1

    private let fileManager: FileManager
    private let limits: SoundPackValidationLimits
    private let workingDirectory: URL
    private let ffmpegExecutableOverride: URL?
    private let ffmpegTimeoutSeconds: TimeInterval

    init(
        workingDirectory: URL? = nil,
        limits: SoundPackValidationLimits = .standard,
        fileManager: FileManager = .default,
        ffmpegExecutableOverride: URL? = nil,
        ffmpegTimeoutSeconds: TimeInterval = AudioImportService.defaultFFmpegTimeoutSeconds
    ) {
        self.fileManager = fileManager
        self.limits = limits
        self.workingDirectory = workingDirectory
            ?? fileManager.temporaryDirectory
                .appendingPathComponent("SimuBoardAudioImports", isDirectory: true)
        self.ffmpegExecutableOverride = ffmpegExecutableOverride
        self.ffmpegTimeoutSeconds = ffmpegTimeoutSeconds.isFinite
            && ffmpegTimeoutSeconds > 0
            && ffmpegTimeoutSeconds <= 300
            ? ffmpegTimeoutSeconds
            : Self.defaultFFmpegTimeoutSeconds
    }

    func prepareImport(
        from sourceURL: URL,
        license: SoundPackAssetLicense? = nil
    ) async throws -> PreparedSoundPackAudio {
        try Task.checkCancellation()
        let sourceByteCount = try SoundPackFileUtilities.validateRegularFile(at: sourceURL)
        guard sourceByteCount > 0, sourceByteCount <= limits.maximumAssetBytes else {
            throw SoundPackError.sizeLimitExceeded(sourceURL.lastPathComponent)
        }

        try fileManager.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )
        let temporaryURL = workingDirectory
            .appendingPathComponent(".import-\(UUID().uuidString).wav")
        do {
            do {
                try Task.checkCancellation()
                _ = try normalize(sourceURL: sourceURL, destinationURL: temporaryURL)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                try? fileManager.removeItem(at: temporaryURL)
                guard sourceURL.pathExtension.lowercased() == "mp3",
                      let ffmpegURL = ffmpegExecutableURL() else {
                    throw SoundPackError.invalidAudio(
                        L10n.format(
                            "系统无法解码此格式（%@）。请改用 WAV、AIFF、CAF 或 M4A；已安装 ffmpeg 时仅对本地 MP3 自动尝试备用转换。",
                            error.localizedDescription
                        )
                    )
                }
                try await normalizeWithFFmpeg(
                    executableURL: ffmpegURL,
                    sourceURL: sourceURL,
                    destinationURL: temporaryURL
                )
            }
            try Task.checkCancellation()
            let hash = try SoundPackFileUtilities.sha256(of: temporaryURL)
            let assetID = SoundPackAssetID(hash)
            let finalURL = workingDirectory.appendingPathComponent("\(hash).wav")

            if fileManager.fileExists(atPath: finalURL.path) {
                let existingHash = try SoundPackFileUtilities.sha256(of: finalURL)
                guard existingHash == hash else {
                    throw SoundPackError.hashMismatch(finalURL.lastPathComponent)
                }
                try? fileManager.removeItem(at: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: finalURL)
            }

            let info = try Self.validateNormalizedAudio(at: finalURL, limits: limits)
            let metadata = SoundPackAudioAsset(
                id: assetID,
                relativePath: "assets/\(hash).wav",
                sha256: hash,
                originalFilename: sourceURL.lastPathComponent,
                durationSeconds: info.durationSeconds,
                sampleRate: info.sampleRate,
                channelCount: info.channelCount,
                byteCount: info.byteCount,
                license: license
            )
            return PreparedSoundPackAudio(
                metadata: metadata,
                normalizedFileURL: finalURL
            )
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            if let cancellation = error as? CancellationError { throw cancellation }
            if let soundPackError = error as? SoundPackError { throw soundPackError }
            throw SoundPackError.invalidAudio(error.localizedDescription)
        }
    }

    func discardPreparedAudio(_ prepared: PreparedSoundPackAudio) throws {
        let root = workingDirectory.standardizedFileURL
        let candidate = prepared.normalizedFileURL.standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(prefix) else {
            throw SoundPackError.unsafePath(candidate.path)
        }
        if fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
        }
    }

    func removeAllPreparedAudio() throws {
        guard fileManager.fileExists(atPath: workingDirectory.path) else { return }
        let values = try workingDirectory.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw SoundPackError.unsafeFile(workingDirectory.path)
        }
        try fileManager.removeItem(at: workingDirectory)
    }

    nonisolated static func validateNormalizedAudio(
        at url: URL,
        limits: SoundPackValidationLimits = .standard
    ) throws -> NormalizedSoundPackAudioInfo {
        let byteCount = try SoundPackFileUtilities.validateRegularFile(at: url)
        guard byteCount > 0, byteCount <= limits.maximumAssetBytes else {
            throw SoundPackError.sizeLimitExceeded(url.lastPathComponent)
        }
        guard url.pathExtension.lowercased() == "wav" else {
            throw SoundPackError.invalidAudio(L10n.tr("规范化资源必须是 WAV"))
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw SoundPackError.invalidAudio(error.localizedDescription)
        }
        let format = file.fileFormat
        let formatID = (format.settings[AVFormatIDKey] as? NSNumber)?.uint32Value
        guard formatID == kAudioFormatLinearPCM,
              format.sampleRate == targetSampleRate,
              format.channelCount == 1,
              format.commonFormat == .pcmFormatInt16 else {
            throw SoundPackError.invalidAudio(L10n.tr("必须为 48 kHz 单声道 16-bit PCM WAV"))
        }
        guard file.length > 0 else {
            throw SoundPackError.invalidAudio(L10n.tr("音频为空"))
        }
        let duration = Double(file.length) / format.sampleRate
        guard duration.isFinite,
              duration >= limits.minimumAudioDurationSeconds,
              duration <= limits.maximumAudioDurationSeconds else {
            throw SoundPackError.invalidAudio(L10n.tr("音频时长超出允许范围"))
        }
        return NormalizedSoundPackAudioInfo(
            durationSeconds: duration,
            byteCount: byteCount,
            sampleRate: Int(format.sampleRate),
            channelCount: Int(format.channelCount)
        )
    }

    nonisolated static func checkedDecodedPCMByteCount(
        sampleRate: Double,
        channelCount: Int,
        frameLength: Int64,
        bytesPerSample: Int
    ) throws -> Int64 {
        guard sampleRate.isFinite,
              sampleRate >= minimumSourceSampleRate,
              sampleRate <= maximumSourceSampleRate else {
            throw SoundPackError.invalidAudio(L10n.tr("源音频采样率超出安全范围"))
        }
        guard channelCount > 0, channelCount <= maximumSourceChannelCount else {
            throw SoundPackError.invalidAudio(L10n.tr("源音频声道数超出安全范围"))
        }
        guard frameLength > 0, frameLength <= Int64(AVAudioFrameCount.max) else {
            throw SoundPackError.sizeLimitExceeded(L10n.tr("源音频帧数过多"))
        }
        guard bytesPerSample > 0 else {
            throw SoundPackError.invalidAudio(L10n.tr("源音频采样格式无效"))
        }

        let frameCount = UInt64(frameLength)
        let (sampleCount, sampleCountOverflowed) = frameCount.multipliedReportingOverflow(
            by: UInt64(channelCount)
        )
        guard !sampleCountOverflowed else {
            throw SoundPackError.sizeLimitExceeded(L10n.tr("源音频解码体积溢出"))
        }
        let (decodedByteCount, byteCountOverflowed) = sampleCount.multipliedReportingOverflow(
            by: UInt64(bytesPerSample)
        )
        guard !byteCountOverflowed,
              decodedByteCount <= UInt64(maximumDecodedPCMBytes),
              decodedByteCount <= UInt64(Int64.max) else {
            throw SoundPackError.sizeLimitExceeded(L10n.tr("源音频解码后超过 64 MiB"))
        }
        return Int64(decodedByteCount)
    }

    private func normalize(sourceURL: URL, destinationURL: URL) throws -> Double {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        let sourceFormat = sourceFile.processingFormat
        let bytesPerSample: Int
        switch sourceFormat.commonFormat {
        case .pcmFormatFloat32, .pcmFormatInt32:
            bytesPerSample = 4
        case .pcmFormatFloat64:
            bytesPerSample = 8
        case .pcmFormatInt16:
            bytesPerSample = 2
        default:
            throw SoundPackError.invalidAudio(L10n.tr("源音频不是可安全解码的 PCM 格式"))
        }
        _ = try Self.checkedDecodedPCMByteCount(
            sampleRate: sourceFormat.sampleRate,
            channelCount: Int(sourceFormat.channelCount),
            frameLength: sourceFile.length,
            bytesPerSample: bytesPerSample
        )

        let sourceDuration = Double(sourceFile.length) / sourceFormat.sampleRate
        guard sourceDuration.isFinite,
              sourceDuration >= limits.minimumAudioDurationSeconds,
              sourceDuration <= limits.maximumAudioDurationSeconds else {
            throw SoundPackError.invalidAudio(
                L10n.format(
                    "源音频时长必须介于 %@–%@ 秒",
                    "\(limits.minimumAudioDurationSeconds)",
                    "\(limits.maximumAudioDurationSeconds)"
                )
            )
        }
        guard sourceFile.length <= Int64(AVAudioFrameCount.max) else {
            throw SoundPackError.sizeLimitExceeded(L10n.tr("源音频帧数过多"))
        }
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(sourceFile.length)
        ) else {
            throw SoundPackError.invalidAudio(L10n.tr("无法创建源音频缓冲区"))
        }
        try sourceFile.read(into: sourceBuffer)
        guard sourceBuffer.frameLength > 0 else {
            throw SoundPackError.invalidAudio(L10n.tr("源音频为空"))
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: sourceBuffer.format, to: targetFormat) else {
            throw SoundPackError.invalidAudio(L10n.tr("无法创建 48 kHz 单声道转换器"))
        }

        let estimatedFrames = ceil(
            Double(sourceBuffer.frameLength) * Self.targetSampleRate / sourceBuffer.format.sampleRate
        )
        guard estimatedFrames.isFinite,
              estimatedFrames > 0,
              estimatedFrames <= Double(AVAudioFrameCount.max - 128) else {
            throw SoundPackError.sizeLimitExceeded(L10n.tr("转换后的音频帧数过多"))
        }
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(estimatedFrames) + 128
        ) else {
            throw SoundPackError.invalidAudio(L10n.tr("无法创建目标音频缓冲区"))
        }

        var providedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if providedInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            providedInput = true
            inputStatus.pointee = .haveData
            return sourceBuffer
        }
        if let conversionError {
            throw SoundPackError.invalidAudio(conversionError.localizedDescription)
        }
        guard status == .haveData || status == .endOfStream,
              outputBuffer.frameLength > 0 else {
            throw SoundPackError.invalidAudio(L10n.tr("音频转换未产生数据"))
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let outputFile = try AVAudioFile(
            forWriting: destinationURL,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try outputFile.write(from: outputBuffer)
        return Double(outputBuffer.frameLength) / Self.targetSampleRate
    }

    private func ffmpegExecutableURL() -> URL? {
        if let ffmpegExecutableOverride,
           fileManager.isExecutableFile(atPath: ffmpegExecutableOverride.path) {
            return ffmpegExecutableOverride
        }
        let candidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            URL(fileURLWithPath: "/usr/local/bin/ffmpeg"),
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private func normalizeWithFFmpeg(
        executableURL: URL,
        sourceURL: URL,
        destinationURL: URL
    ) async throws {
        try Task.checkCancellation()
        let process = Process()
        let rawMaximumOutputBytes = ceil(
            (limits.maximumAudioDurationSeconds + 0.25) * Self.targetSampleRate * 2
        )
        guard rawMaximumOutputBytes.isFinite,
              rawMaximumOutputBytes > 0,
              rawMaximumOutputBytes <= Double(Int64.max - 65_536) else {
            throw SoundPackError.invalidAudio(L10n.tr("备用音频转换时长限制无效"))
        }
        let maximumOutputBytes = Int64(rawMaximumOutputBytes) + 65_536
        process.executableURL = executableURL
        process.arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-nostdin",
            "-y",
            // The fallback is intentionally limited to a local, self-contained
            // MP3. This prevents playlists or crafted media from making ffmpeg
            // follow HTTP(S) or other nested protocols behind the user's back.
            "-protocol_whitelist", "file",
            "-f", "mp3",
            "-i", sourceURL.path,
            "-map_metadata", "-1",
            "-vn",
            "-ac", "1",
            "-ar", "48000",
            "-c:a", "pcm_s16le",
            // Bound disk use without turning an overlong source into a valid
            // clipped sample. The allowance is deliberately longer than the
            // accepted duration, so the validator below still rejects it.
            "-fs", String(maximumOutputBytes),
            destinationURL.path,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        // A pipe that is drained only after waitUntilExit can deadlock if a
        // malformed input makes ffmpeg produce enough diagnostics to fill it.
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            if process.isRunning {
                _ = stopFFmpegProcess(process)
            }
            throw SoundPackError.invalidAudio(
                L10n.format("无法启动备用音频转换器：%@", error.localizedDescription)
            )
        }

        do {
            try await waitForFFmpegProcess(process)
        } catch {
            let stopped = stopFFmpegProcess(process)
            try? fileManager.removeItem(at: destinationURL)
            guard stopped else {
                throw SoundPackError.invalidAudio(L10n.tr("无法安全终止备用音频转换器"))
            }
            throw error
        }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw SoundPackError.invalidAudio(
                L10n.tr("备用音频转换失败；系统也无法解码此格式，请改用 WAV、AIFF、CAF 或 M4A。")
            )
        }
        _ = try Self.validateNormalizedAudio(at: destinationURL, limits: limits)
    }

    private func waitForFFmpegProcess(_ process: Process) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + ffmpegTimeoutSeconds
        while process.isRunning {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw SoundPackError.invalidAudio(
                    L10n.format(
                        "备用音频转换超时（最长 %@ 秒）",
                        "\(Int(ceil(ffmpegTimeoutSeconds)))"
                    )
                )
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func stopFFmpegProcess(_ process: Process) -> Bool {
        guard process.isRunning else { return true }
        process.terminate()
        waitSynchronouslyForProcess(
            process,
            until: ProcessInfo.processInfo.systemUptime + Self.ffmpegTerminationGraceSeconds
        )
        guard process.isRunning else { return true }

        let processIdentifier = process.processIdentifier
        if processIdentifier > 0 {
            _ = Darwin.kill(processIdentifier, SIGKILL)
        }
        waitSynchronouslyForProcess(
            process,
            until: ProcessInfo.processInfo.systemUptime + Self.ffmpegKillGraceSeconds
        )
        return !process.isRunning
    }

    private func waitSynchronouslyForProcess(_ process: Process, until deadline: TimeInterval) {
        while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: Self.ffmpegPollIntervalSeconds)
        }
    }
}
