import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var model: AppModel
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var permission: InputMonitoringPermissionManager

    init(model: AppModel) {
        _model = ObservedObject(wrappedValue: model)
        _settings = ObservedObject(wrappedValue: model.settings)
        _permission = ObservedObject(wrappedValue: model.permission)
    }

    var body: some View {
        VStack(spacing: 14) {
            header

            if !permission.isGranted {
                permissionCard
            }

            if let message = monitoringFailureMessage {
                monitoringFailureCard(message)
            }

            if let message = model.audioError {
                audioFailureCard(message)
            }

            profileSection
            soundSection
            footer
        }
        .padding(16)
        .frame(width: 340)
        .tint(Color(red: 0.72, green: 0.88, blue: 0.33))
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 40, height: 40)
                .background(Color(red: 0.82, green: 1, blue: 0.42), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text("SimuBoard")
                    .font(.headline)
                Text(headerStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Toggle("启用声音", isOn: $settings.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private func monitoringFailureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("键盘监听未启动", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("重试监听") { model.retryKeyboardMonitor() }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func audioFailureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("声音暂时不可用", systemImage: "speaker.slash.fill")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("需要输入监控权限", systemImage: "keyboard.badge.eye")
                .font(.subheadline.weight(.semibold))
            Text("SimuBoard 只读取按键编号来播放声音，不读取或保存输入内容。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("如果系统开关已经打开但这里仍显示等待，请选中旧 SimuBoard，点列表下方“−”删除，再重新添加 /Applications/SimuBoard.app。完成后退出并重新打开应用。")
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("请求授权") {
                    model.requestInputMonitoring()
                    if !permission.isGranted {
                        model.openInputMonitoringSettings()
                    }
                    dismiss()
                }
                    .buttonStyle(.borderedProminent)
                Button("打开系统设置") {
                    model.openInputMonitoringSettings()
                    dismiss()
                }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.24)))
    }

    private var profileSection: some View {
        GroupBox("轴体音色") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("轴体", selection: $settings.selectedProfileID) {
                    ForEach(SwitchProfile.allCases) { profile in
                        Text("\(profile.displayName) · \(profile.family)")
                            .tag(profile.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                HStack(spacing: 6) {
                    Text(settings.selectedProfile.family)
                    Text(settings.selectedProfile.tone)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Button {
                    model.preview()
                } label: {
                    Label("试听当前轴体", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
    }

    private var soundSection: some View {
        GroupBox("声音设置") {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("音量")
                        Spacer()
                        Text("\(Int(settings.volume * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.volume, in: 0...1, step: 0.01)
                        .accessibilityLabel("音量")
                }

                Divider()
                Toggle("播放按键回弹音", isOn: $settings.playsReleaseSound)
                    .disabled(!settings.selectedProfile.supportsReleaseSound)
                if !settings.selectedProfile.supportsReleaseSound {
                    Text("此音色来自单次完整按键录音，没有独立回弹片段。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Toggle("加入轻微音高变化", isOn: $settings.usesPitchVariation)
            }
            .font(.subheadline)
            .padding(.top, 4)
        }
    }

    private var footer: some View {
        let status = statusPresentation
        return HStack {
            Label(status.text, systemImage: status.symbol)
            .font(.caption2)
            .foregroundStyle(status.color)

            Spacer()
            Button("收起") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
    }

    private var headerStatusText: String {
        guard settings.isEnabled else { return "声音已暂停" }
        switch model.monitoringState {
        case .running: return "正在监听键盘"
        case .waitingForPermission: return "等待输入监控授权"
        case .failed: return "键盘监听启动失败"
        case .stopped: return "键盘监听已停止"
        }
    }

    private var monitoringFailureMessage: String? {
        guard case let .failed(message) = model.monitoringState else { return nil }
        return message
    }

    private var statusPresentation: (text: String, symbol: String, color: Color) {
        switch model.monitoringState {
        case .running:
            return ("输入监控正在运行", "checkmark.shield.fill", .secondary)
        case .waitingForPermission:
            return ("等待授权", "exclamationmark.shield.fill", .orange)
        case .failed:
            return ("监听启动失败", "xmark.shield.fill", .red)
        case .stopped:
            return ("监听已停止", "pause.circle.fill", .secondary)
        }
    }
}

#Preview {
    MenuBarView(model: AppModel(startsServices: false))
}
