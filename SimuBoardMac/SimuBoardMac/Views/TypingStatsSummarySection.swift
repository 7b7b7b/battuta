import SwiftUI

@MainActor
struct TypingStatsSummarySection: View {
    @ObservedObject var model: TypingStatsModel
    @ObservedObject var settings: AppSettings
    let onOpenDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                BattutaSectionHeading(
                    "输入统计",
                    subtitle: "聚合保存在本机",
                    symbol: "chart.bar.fill"
                )
                Spacer()
                Toggle("记录本地输入统计", isOn: $settings.isTypingStatsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("记录本地输入统计")
            }

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
                HStack {
                    Label("查看详细统计", systemImage: "chart.xyaxis.line")
                    Spacer()
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .help("查看今日、应用、历史和逐键热力图")
        }
        .padding(BattutaVisualStyle.cardPadding)
        .battutaPanel()
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
            HStack(spacing: 10) {
                compactMetric(
                    title: "今日字符",
                    value: statsCount(snapshot.today.characterCount),
                    symbol: "keyboard"
                )
                compactMetric(
                    title: "今日峰值",
                    value: "\(snapshot.today.peakCPS)/秒",
                    symbol: "bolt.fill"
                )
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

    private func compactMetric(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            BattutaIconTile(
                symbol: symbol,
                tint: BattutaVisualStyle.accentStrong,
                size: 30,
                symbolSize: 12
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BattutaVisualStyle.recessed, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
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
