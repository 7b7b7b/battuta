import SwiftUI

@MainActor
struct UpdateSection: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var controller: UpdateController

    init(controller: UpdateController) {
        _controller = ObservedObject(wrappedValue: controller)
    }

    var body: some View {
        GroupBox("软件更新") {
            VStack(alignment: .leading, spacing: 10) {
                preferenceContent
                Divider()
                resultContent
                controls
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var preferenceContent: some View {
        switch controller.automaticCheckPreference {
        case .undecided:
            VStack(alignment: .leading, spacing: 8) {
                Label("允许打开菜单时检查更新？", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                privacyText
                HStack {
                    Button("开启") { controller.enableAutomaticChecks() }
                        .buttonStyle(.borderedProminent)
                    Button("暂不开启") { controller.disableAutomaticChecks() }
                        .buttonStyle(.bordered)
                }
            }

        case .enabled, .disabled:
            VStack(alignment: .leading, spacing: 6) {
                Toggle("打开菜单时自动检查更新", isOn: automaticCheckBinding)
                privacyText
            }
        }
    }

    private var privacyText: some View {
        Text("开启后，每次打开菜单都会触发更新判断，自动联网请求至少间隔 5 分钟；手动检查至少间隔 65 秒。GitHub 会收到 IP 地址和常规网络请求信息；SimuBoard 不会上传按键、输入内容、音色设置或设备标识。")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var resultContent: some View {
        if let release = controller.availableRelease {
            VStack(alignment: .leading, spacing: 6) {
                Label("发现新版本 \(release.version.description)", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                Button {
                    openURL(release.releaseURL)
                } label: {
                    Label("前往 GitHub 下载", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let snapshot = controller.state.snapshot {
            switch snapshot.result {
            case .updateAvailable:
                EmptyView()
            case let .upToDate(version):
                Label("已是最新版 \(version.description)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            case let .installedVersionIsNewer(latestVersion):
                Label(
                    "当前安装版本高于公开版本 \(latestVersion.description)",
                    systemImage: "hammer.fill"
                )
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        } else {
            Text("尚未检查更新")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if case let .failed(failure, _) = controller.state {
            failureLabel(failure)
        }
    }

    private var controls: some View {
        HStack {
            if controller.state.isChecking {
                ProgressView()
                    .controlSize(.small)
                Text("正在检查…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("检查更新") { controller.checkManually() }
                .buttonStyle(.bordered)
                .disabled(controller.state.isChecking)
        }
    }

    @ViewBuilder
    private func failureLabel(_ failure: UpdateCheckFailure) -> some View {
        switch failure {
        case .offline:
            Label("当前离线，稍后可重试", systemImage: "wifi.slash")
                .failureCaptionStyle()
        case .timedOut:
            Label("连接 GitHub 超时，稍后可重试", systemImage: "clock.badge.exclamationmark")
                .failureCaptionStyle()
        case let .requestedTooSoon(retryAt):
            Label {
                Text("刚刚检查过，可于 \(retryAt, style: .time) 后再次手动检查")
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .failureCaptionStyle()
        case let .rateLimited(retryAt):
            Label {
                Text("GitHub 暂时限制请求，可于 \(retryAt, style: .time) 后重试")
            } icon: {
                Image(systemName: "hourglass")
            }
            .failureCaptionStyle()
        case .noPublishedRelease:
            Label("GitHub 上暂时没有公开版本", systemImage: "shippingbox")
                .failureCaptionStyle()
        case .apiVersionRetired:
            Label("更新服务需要升级，请稍后手动查看 GitHub", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .failureCaptionStyle()
        case .invalidInstalledVersion, .invalidResponse:
            Label("版本信息格式异常", systemImage: "exclamationmark.triangle")
                .failureCaptionStyle()
        case .serverUnavailable:
            Label("暂时无法连接 GitHub，稍后可重试", systemImage: "network.slash")
                .failureCaptionStyle()
        }
    }

    private var automaticCheckBinding: Binding<Bool> {
        Binding(
            get: { controller.automaticCheckPreference == .enabled },
            set: { enabled in
                if enabled {
                    controller.enableAutomaticChecks()
                } else {
                    controller.disableAutomaticChecks()
                }
            }
        )
    }

}

private extension View {
    func failureCaptionStyle() -> some View {
        font(.caption2)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
private let previewRelease = try! ReleaseSummary(
    tagName: "v0.4.0",
    releaseURL: URL(string: "https://github.com/7b7b7b/simuboard/releases/tag/v0.4.0")!,
    publishedAt: Date()
)

#Preview("首次授权") {
    UpdateSection(
        controller: .preview(
            state: .idle(cached: nil),
            preference: .undecided
        )
    )
    .padding()
    .frame(width: 340)
}

#Preview("发现更新") {
    UpdateSection(
        controller: .preview(
            state: .completed(
                UpdateCheckSnapshot(
                    result: .updateAvailable(previewRelease),
                    checkedAt: Date()
                )
            )
        )
    )
    .padding()
    .frame(width: 340)
}

#Preview("离线") {
    UpdateSection(
        controller: .preview(
            state: .failed(.offline, cached: nil)
        )
    )
    .padding()
    .frame(width: 340)
}
#endif
