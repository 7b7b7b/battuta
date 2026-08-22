import Foundation
import SwiftUI

private enum TypingKeyCountScope: String, CaseIterable, Identifiable {
    case today = "今日"
    case allTime = "累计"

    var id: Self { self }
}

@MainActor
struct TypingStatsKeyboardView: View {
    let snapshot: TypingStatsSnapshot
    @State private var scope: TypingKeyCountScope = .today

    private let layout = KeyboardLayoutCatalog.ansiTKL
    private let extendedRows = TypingStatsExtendedKeyboard.rows

    private var counts: [UInt16: Int64] {
        switch scope {
        case .today: snapshot.todayKeyCounts
        case .allTime: snapshot.allTimeKeyCounts
        }
    }

    private var totalPresses: Int64 {
        counts.values.reduce(0, +)
    }

    private var maximumCount: Int64 {
        counts.values.max() ?? 0
    }

    private var knownKeys: [KeyboardKeyDescriptor] {
        layout.keys + extendedRows.flatMap(\.keys)
    }

    private var knownKeysByCode: [UInt16: KeyboardKeyDescriptor] {
        Dictionary(uniqueKeysWithValues: knownKeys.map { ($0.keyCode, $0) })
    }

    private var otherKeys: [KeyboardKeyDescriptor] {
        counts.keys
            .filter { knownKeysByCode[$0] == nil }
            .sorted()
            .map { keyCode in
                KeyboardKeyDescriptor(
                    id: KeyboardKeyID("stats.other.\(keyCode)"),
                    keyCode: keyCode,
                    label: "键码 \(keyCode)",
                    row: .r4
                )
            }
    }

    private var mostPressedKey: (label: String, count: Int64)? {
        guard let entry = counts.max(by: {
            if $0.value != $1.value { return $0.value < $1.value }
            return $0.key > $1.key
        }), entry.value > 0 else {
            return nil
        }
        return (knownKeysByCode[entry.key]?.label ?? "键码 \(entry.key)", entry.value)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("逐键按下统计")
                            .font(.headline)
                        Text("每个键显示物理按下次数，颜色越亮表示使用越频繁。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("统计范围", selection: $scope) {
                        ForEach(TypingKeyCountScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                HStack(spacing: 12) {
                    KeyboardMetricCard(
                        title: scope == .today ? "今日物理按下" : "累计物理按下",
                        value: statsCount(totalPresses),
                        detail: "不重复计算长按连发",
                        symbol: "keyboard"
                    )
                    KeyboardMetricCard(
                        title: "最常用按键",
                        value: mostPressedKey?.label ?? "暂无",
                        detail: mostPressedKey.map { "\(statsCount($0.count)) 次" } ?? "还没有按键记录",
                        symbol: "flame.fill"
                    )
                }

                if totalPresses == 0 {
                    Label(
                        scope == .today
                            ? "今天还没有按键记录；开始输入后这里会逐键点亮。"
                            : "还没有累计按键记录；开始输入后这里会逐键点亮。",
                        systemImage: "keyboard"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                }

                GroupBox("完整键盘热力图") {
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(layout.rows) { row in
                                HStack(spacing: 4) {
                                    ForEach(row.keys) { key in
                                        TypingStatsKeycap(
                                            key: key,
                                            count: counts[key.keyCode, default: 0],
                                            maximumCount: maximumCount,
                                            compactHeight: row.id == "function"
                                        )
                                    }
                                }
                                .padding(.bottom, row.id == "function" ? 8 : 0)
                            }

                            Divider()
                                .padding(.vertical, 8)

                            Text("导航键、扩展功能键、数字键盘与国际键")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 2)

                            ForEach(extendedRows) { row in
                                HStack(spacing: 4) {
                                    ForEach(row.keys) { key in
                                        TypingStatsKeycap(
                                            key: key,
                                            count: counts[key.keyCode, default: 0],
                                            maximumCount: maximumCount,
                                            compactHeight: false
                                        )
                                    }
                                }
                            }

                            if !otherKeys.isEmpty {
                                Text("其他已识别键")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                HStack(spacing: 4) {
                                    ForEach(otherKeys) { key in
                                        TypingStatsKeycap(
                                            key: key,
                                            count: counts[key.keyCode, default: 0],
                                            maximumCount: maximumCount,
                                            compactHeight: false
                                        )
                                    }
                                }
                            }
                        }
                        .padding(18)
                        .accessibilityHidden(totalPresses == 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 520, alignment: .center)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(
                        "按下计数包含 Shift、Command、回车、退格和方向键；长按产生的系统自动重复不增加物理按下次数。"
                    )
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }
}

@MainActor
private struct KeyboardMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.green.opacity(0.17)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)，\(detail)")
    }
}

@MainActor
private struct TypingStatsKeycap: View {
    let key: KeyboardKeyDescriptor
    let count: Int64
    let maximumCount: Int64
    let compactHeight: Bool

    private var width: CGFloat {
        max(38, CGFloat(key.widthUnits) * 38 + CGFloat(max(0, key.widthUnits - 1)) * 4)
    }

    private var intensity: Double {
        guard count > 0, maximumCount > 0 else { return 0 }
        return log(Double(count) + 1) / log(Double(maximumCount) + 1)
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(key.label)
                .font(key.widthUnits > 1.2 ? .caption2 : .caption)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(statsCompactKeyCount(count))
                .font(.caption2.weight(count > 0 ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(count > 0 ? .primary : .tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(.horizontal, 4)
        .frame(
            width: width,
            height: compactHeight ? 42 : 50
        )
        .background(keycapColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.green.opacity(count > 0 ? 0.32 + intensity * 0.38 : 0.12))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(key.label)
        .accessibilityValue("\(count) 次")
        .help("\(key.label)：\(statsCount(count)) 次")
    }

    private var keycapColor: Color {
        guard count > 0 else { return Color.secondary.opacity(0.055) }
        return Color.green.opacity(0.10 + intensity * 0.58)
    }
}

private enum TypingStatsExtendedKeyboard {
    static let rows: [KeyboardLayoutRow] = [
        row("navigation", [
            key("help", 114, "help"), key("home", 115, "home"),
            key("pageUp", 116, "page up"), key("forwardDelete", 117, "⌦"),
            key("end", 119, "end"), key("pageDown", 121, "page down"),
        ]),
        row("extendedFunction", [
            key("f13", 105, "F13"), key("f14", 107, "F14"),
            key("f15", 113, "F15"), key("f16", 106, "F16"),
            key("f17", 64, "F17"), key("f18", 79, "F18"),
            key("f19", 80, "F19"), key("f20", 90, "F20"),
        ]),
        row("keypadTop", [
            key("keypadClear", 71, "clear"), key("keypadEqual", 81, "="),
            key("keypadDivide", 75, "÷"), key("keypadMultiply", 67, "×"),
            key("keypadMinus", 78, "−"),
        ]),
        row("keypadUpper", [
            key("keypad7", 89, "7"), key("keypad8", 91, "8"),
            key("keypad9", 92, "9"), key("keypadPlus", 69, "+"),
        ]),
        row("keypadMiddle", [
            key("keypad4", 86, "4"), key("keypad5", 87, "5"),
            key("keypad6", 88, "6"),
        ]),
        row("keypadLower", [
            key("keypad1", 83, "1"), key("keypad2", 84, "2"),
            key("keypad3", 85, "3"), key("keypadEnter", 76, "enter", width: 1.5),
        ]),
        row("keypadBottom", [
            key("keypad0", 82, "0", width: 2), key("keypadDecimal", 65, "."),
        ]),
        row("international", [
            key("isoSection", 10, "§/±"), key("jisYen", 93, "¥"),
            key("jisUnderscore", 94, "＿"), key("jisKeypadComma", 95, "，"),
            key("jisEisu", 102, "英数"), key("jisKana", 104, "かな"),
        ]),
        row("media", [
            key("volumeUp", 72, "音量+", width: 1.5),
            key("volumeDown", 73, "音量−", width: 1.5),
            key("mute", 74, "静音", width: 1.5),
        ]),
    ]

    private static func row(
        _ id: String,
        _ keys: [KeyboardKeyDescriptor]
    ) -> KeyboardLayoutRow {
        KeyboardLayoutRow(id: "stats.\(id)", keys: keys)
    }

    private static func key(
        _ id: String,
        _ keyCode: UInt16,
        _ label: String,
        width: Double = 1
    ) -> KeyboardKeyDescriptor {
        KeyboardKeyDescriptor(
            id: KeyboardKeyID("stats.\(id)"),
            keyCode: keyCode,
            label: label,
            row: .r4,
            widthUnits: width
        )
    }
}

private func statsCompactKeyCount(_ count: Int64) -> String {
    guard count >= 10_000 else { return statsCount(count) }
    if count >= 100_000_000 {
        return compactChineseNumber(Double(count) / 100_000_000, unit: "亿")
    }
    return compactChineseNumber(Double(count) / 10_000, unit: "万")
}

private func compactChineseNumber(_ value: Double, unit: String) -> String {
    let decimals = value < 100 ? 1 : 0
    return value.formatted(
        .number.precision(.fractionLength(0...decimals)).rounded(rule: .down)
    ) + unit
}
