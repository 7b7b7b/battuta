import SwiftUI

@MainActor
struct TypingStatsSummarySection: View {
    @ObservedObject var model: TypingStatsModel
    @ObservedObject var settings: AppSettings
    let onOpenDetails: () -> Void

    var body: some View {
        GroupBox("输入统计") {
            VStack(alignment: .leading, spacing: 11) {
                Toggle("记录本地输入统计", isOn: $settings.isTypingStatsEnabled)
                    .font(.subheadline)

                Text("仅保存聚合数量、物理键码、时间与前台应用；不保存输入内容或按键顺序。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.isTypingStatsEnabled {
                    content
                } else {
                    Label("统计已暂停，已有历史数据仍会保留。", systemImage: "pause.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: onOpenDetails) {
                    Label("打开详细输入统计", systemImage: "chart.xyaxis.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("查看今日、应用、历史和逐键热力图")
            }
            .padding(.top, 4)
        }
        .task { await refreshWhileVisible() }
        .onChange(of: settings.isTypingStatsEnabled) { enabled in
            guard enabled else { return }
            Task { await model.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = model.snapshot {
            loadedContent(snapshot)
        } else {
            switch model.sourceStatus {
            case .checking, .available:
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在读取本地统计…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadedContent(_ snapshot: TypingStatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statsCount(snapshot.today.characterCount))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Text("今日字符数")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("今日字符数")
                .accessibilityValue("\(snapshot.today.characterCount) 个字符")

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(snapshot.today.peakCPS) 字符/秒")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                    Text("今日峰值速度")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("今日峰值速度")
                .accessibilityValue("\(snapshot.today.peakCPS) 字符每秒")
            }

            Label(
                "今日最多应用：\(snapshot.today.topAppName ?? "暂无")",
                systemImage: "app.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if let message = model.staleDataMessage {
                Label("统计暂未更新：\(message)", systemImage: "arrow.clockwise.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func refreshWhileVisible() async {
        await model.refresh()
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            await model.refresh()
        }
    }
}
