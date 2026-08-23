import SwiftUI

@MainActor
struct AudioSplitEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var editor: SoundPackEditorModel
    let draft: SoundPackSplitDraft

    @State private var splitTime: TimeInterval
    @State private var releaseEndTime: TimeInterval

    init(editor: SoundPackEditorModel, draft: SoundPackSplitDraft) {
        self.editor = editor
        self.draft = draft
        let minimumSplit = 0.012
        let maximumSplit = max(minimumSplit, draft.analysis.duration - 0.020)
        let initialSplit = max(
            minimumSplit,
            min(maximumSplit, draft.analysis.suggestion.splitTime)
        )
        let suggestedReleaseEnd = draft.analysis.suggestion.suggestedReleaseEndTime
            ?? draft.analysis.duration
        _splitTime = State(initialValue: initialSplit)
        _releaseEndTime = State(
            initialValue: max(
                initialSplit + 0.013,
                min(draft.analysis.duration, suggestedReleaseEnd)
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                BattutaIconTile(
                    symbol: "scissors",
                    tint: BattutaVisualStyle.accentStrong,
                    size: 40,
                    symbolSize: 17
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text("拆分完整击键")
                        .font(.title2.weight(.semibold))
                    Text("调整下方切点，使左侧只保留按下、右侧从回弹瞬态开始。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                confidenceBadge
            }
            .padding(20)

            BattutaVisualStyle.separator.opacity(0.65).frame(height: 1)

            VStack(alignment: .leading, spacing: 18) {
                AudioSplitWaveform(
                    analysis: draft.analysis,
                    splitTime: splitTime,
                    releaseEndTime: releaseEndTime
                )
                .frame(height: 190)

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await editor.previewSplit(
                                draft: draft,
                                splitTime: splitTime,
                                releaseEndTime: releaseEndTime,
                                phase: .press
                            )
                        }
                    } label: {
                        Label("试听按下", systemImage: "play.fill")
                    }
                    Button {
                        Task {
                            await editor.previewSplit(
                                draft: draft,
                                splitTime: splitTime,
                                releaseEndTime: releaseEndTime,
                                phase: .release
                            )
                        }
                    } label: {
                        Label("试听回弹", systemImage: "play.fill")
                    }
                    Spacer()
                    if editor.isWorking {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在生成试听…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(editor.isWorking)

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label("按下 / 回弹切点", systemImage: "scissors")
                        Spacer()
                        Text(timeLabel(splitTime))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $splitTime,
                        in: minimumSegment...maximumSplit,
                        step: 0.001
                    )
                    Text("建议：\(timeLabel(draft.analysis.suggestion.splitTime)) · 回弹瞬态约在 \(timeLabel(draft.analysis.suggestion.releaseTransientTime))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .battutaPanel(radius: BattutaVisualStyle.compactRadius)

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label("回弹结束", systemImage: "stop.fill")
                        Spacer()
                        Text(timeLabel(releaseEndTime))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $releaseEndTime,
                        in: minimumReleaseEnd...draft.analysis.duration,
                        step: 0.001
                    )
                    Text("如果录音末尾还有下一次击键，可提前结束，避免混入下一个声音。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .battutaPanel(radius: BattutaVisualStyle.compactRadius)

                if !draft.analysis.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(draft.analysis.warnings).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { warning in
                            Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(20)

            BattutaVisualStyle.separator.opacity(0.65).frame(height: 1)

            HStack {
                Text("将设置到：\(draft.target.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") {
                    editor.cancelSplit()
                    dismiss()
                }
                Button("拆分并导入") {
                    Task {
                        let succeeded = await editor.confirmSplit(
                            draft: draft,
                            splitTime: splitTime,
                            releaseEndTime: releaseEndTime
                        )
                        if succeeded { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(editor.isWorking)
            }
            .padding(16)
        }
        .frame(width: 760, height: 630)
        .battutaWindowGlass(providesBackdrop: true)
        .battutaConfigureContainingWindow()
        .tint(BattutaVisualStyle.actionAccent)
        .interactiveDismissDisabled(editor.isWorking)
        .onChange(of: splitTime) { newValue in
            if releaseEndTime < newValue + minimumReleaseGap {
                releaseEndTime = min(draft.analysis.duration, newValue + minimumReleaseGap)
            }
        }
        .onDisappear {
            editor.discardSplitSource(for: draft)
        }
    }

    private var confidenceBadge: some View {
        let confidence = max(0, min(1, draft.analysis.suggestion.confidence))
        return BattutaStatusPill(
            title: "置信度 \(confidence.formatted(.percent.precision(.fractionLength(0))))",
            symbol: confidence >= 0.7 ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
            tint: confidence >= 0.7 ? BattutaVisualStyle.accentStrong : .orange
        )
    }

    private var minimumSegment: TimeInterval { 0.012 }
    private var minimumReleaseGap: TimeInterval { minimumSegment + 0.001 }
    private var maximumSplit: TimeInterval {
        max(minimumSegment, draft.analysis.duration - 0.020)
    }
    private var minimumReleaseEnd: TimeInterval {
        min(draft.analysis.duration, splitTime + minimumReleaseGap)
    }

    private func timeLabel(_ time: TimeInterval) -> String {
        "\((time * 1_000).formatted(.number.precision(.fractionLength(0)))) ms"
    }
}

private struct AudioSplitWaveform: View {
    let analysis: AudioSplitAnalysis
    let splitTime: TimeInterval
    let releaseEndTime: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BattutaVisualStyle.surface)

                HStack(spacing: 0) {
                    BattutaVisualStyle.accent.opacity(0.10)
                        .frame(width: xPosition(for: splitTime, width: proxy.size.width))
                    BattutaVisualStyle.cyan.opacity(0.08)
                    Color.secondary.opacity(0.08)
                        .frame(width: max(0, proxy.size.width - xPosition(for: releaseEndTime, width: proxy.size.width)))
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Canvas { context, size in
                    guard analysis.duration > 0, !analysis.waveform.isEmpty else { return }
                    let midY = size.height / 2
                    let amplitude = max(1, size.height * 0.43)
                    var path = Path()
                    for point in analysis.waveform {
                        let x = CGFloat(point.time / analysis.duration) * size.width
                        let upper = midY - CGFloat(point.maximum) * amplitude
                        let lower = midY - CGFloat(point.minimum) * amplitude
                        path.move(to: CGPoint(x: x, y: upper))
                        path.addLine(to: CGPoint(x: x, y: lower))
                    }
                    context.stroke(path, with: .color(BattutaVisualStyle.accentStrong.opacity(0.90)), lineWidth: 1)

                    var center = Path()
                    center.move(to: CGPoint(x: 0, y: midY))
                    center.addLine(to: CGPoint(x: size.width, y: midY))
                    context.stroke(center, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
                }
                .padding(8)

                splitMarker(width: proxy.size.width, height: proxy.size.height)
                releaseEndMarker(width: proxy.size.width, height: proxy.size.height)

                regionLabels(width: proxy.size.width)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("击键音频波形")
        .accessibilityValue("切点 \(Int(splitTime * 1_000)) 毫秒")
    }

    private func splitMarker(width: CGFloat, height: CGFloat) -> some View {
        let x = xPosition(for: splitTime, width: width)
        return Rectangle()
            .fill(BattutaVisualStyle.accentStrong)
            .frame(width: 2, height: height)
            .overlay(alignment: .top) {
                Image(systemName: "scissors")
                    .font(.caption)
                    .padding(5)
                    .background(.regularMaterial, in: Circle())
                    .offset(y: 7)
            }
            .position(x: x, y: height / 2)
    }

    private func releaseEndMarker(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.65))
            .frame(width: 1, height: height)
            .position(
                x: xPosition(for: releaseEndTime, width: width),
                y: height / 2
            )
    }

    private func regionLabels(width: CGFloat) -> some View {
        let splitX = xPosition(for: splitTime, width: width)
        let releaseX = xPosition(for: releaseEndTime, width: width)
        return ZStack(alignment: .topLeading) {
            regionLabel("按下", x: splitX / 2, width: width)
            regionLabel("回弹", x: splitX + (releaseX - splitX) / 2, width: width)
            regionLabel("忽略", x: releaseX + (width - releaseX) / 2, width: width)
        }
        .frame(width: width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func regionLabel(_ title: String, x: CGFloat, width: CGFloat) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .position(x: max(24, min(x, width - 24)), y: 18)
    }

    private func xPosition(for time: TimeInterval, width: CGFloat) -> CGFloat {
        guard analysis.duration > 0 else { return 0 }
        return max(0, min(width, CGFloat(time / analysis.duration) * width))
    }
}

private extension AudioSplitAnalysisWarning {
    var message: String {
        switch self {
        case .lowConfidence: "自动切点置信度较低，请仔细检查波形。"
        case .fallbackValleyUsed: "未找到明显回弹瞬态，当前切点使用能量谷值。"
        case .possibleAdditionalKeystroke: "检测到可能的下一次击键，已建议提前结束。"
        case .sourceMayBeClipped: "源录音可能削波，建议降低录音增益后重试。"
        }
    }
}
