import AppKit
import Foundation
import SwiftUI

private enum TypingKeyCountScope: String, CaseIterable, Identifiable {
    case today = "今日"
    case allTime = "累计"

    var id: Self { self }
}

private struct TypingStatsKeyboardPresentation: Equatable {
    static let layout = KeyboardLayoutCatalog.ansiTKL
    static let visualLayout = KeyboardVisualLayoutCatalog.magicKeyboardANSI
    static let extendedRows = KeyboardExtendedLayoutCatalog.rows
    private static let knownKeys = layout.keys + extendedRows.flatMap(\.keys)
    private static let knownKeysByCode = Dictionary(
        uniqueKeysWithValues: knownKeys.map { ($0.keyCode, $0) }
    )
    static let unplacedLayoutKeys = layout.keys.filter { !visualLayout.keyIDs.contains($0.id) }

    let counts: [UInt16: Int64]
    let totalPresses: Int64
    let maximumCount: Int64
    let otherKeys: [KeyboardKeyDescriptor]

    init(snapshot: TypingStatsSnapshot, scope: TypingKeyCountScope) {
        switch scope {
        case .today:
            counts = snapshot.todayKeyCounts
        case .allTime:
            counts = snapshot.allTimeKeyCounts
        }

        totalPresses = counts.values.reduce(0, +)
        maximumCount = counts.values.max() ?? 0
        otherKeys = counts.keys
            .filter { Self.knownKeysByCode[$0] == nil }
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
}

@MainActor
struct TypingStatsKeyboardView: View {
    let snapshot: TypingStatsSnapshot
    @State private var scope: TypingKeyCountScope = .today
    @State private var showsExtendedKeys = false

    private var exposesEmptyKeysToAssistiveTech: Bool {
        NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled
    }

    private var presentation: TypingStatsKeyboardPresentation {
        TypingStatsKeyboardPresentation(snapshot: snapshot, scope: scope)
    }

    var body: some View {
        let presentation = presentation

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 20) {
                        BattutaSectionHeading(
                            "键盘热力图",
                            subtitle: "Apple 紧凑型 Mac 键盘 · US ANSI · 14.5U",
                            symbol: "square.grid.3x3.fill"
                        )

                        Spacer()

                        VStack(alignment: .trailing, spacing: 10) {
                            Picker("统计范围", selection: $scope) {
                                ForEach(TypingKeyCountScope.allCases) { scope in
                                    Text(scope.rawValue).tag(scope)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 150)

                            heatLegend
                        }
                    }

                    Divider()

                    if presentation.totalPresses == 0 {
                        Label(
                            scope == .today
                                ? "今天还没有按键记录；开始输入后键盘会逐键点亮。"
                                : "还没有累计按键记录；开始输入后键盘会逐键点亮。",
                            systemImage: "keyboard"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    TypingStatsKeyboardHeatmap(
                        counts: presentation.counts,
                        maximumCount: presentation.maximumCount,
                        exposesEmptyKeyMetadata: exposesEmptyKeysToAssistiveTech
                    )
                    .equatable()
                    .padding(.vertical, 4)
                    .accessibilityHidden(presentation.totalPresses == 0)

                    Divider()

                    DisclosureGroup(isExpanded: $showsExtendedKeys) {
                        TypingStatsKeyboardExtendedSection(
                            counts: presentation.counts,
                            maximumCount: presentation.maximumCount,
                            otherKeys: presentation.otherKeys,
                            exposesEmptyMetadata: exposesEmptyKeysToAssistiveTech
                        )
                        .equatable()
                            .padding(.top, 12)
                    } label: {
                        Text("外接键盘与扩展按键")
                            .font(.subheadline.weight(.medium))
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
                .padding(BattutaVisualStyle.cardPadding)
                .battutaPanel()
            }
            .padding(20)
            .frame(maxWidth: 1_080)
            .frame(maxWidth: .infinity)
        }
    }

    private var heatLegend: some View {
        HStack(spacing: 6) {
            Text("低")
            ForEach([0.10, 0.25, 0.40, 0.56], id: \.self) { opacity in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(BattutaVisualStyle.accent.opacity(opacity))
                    .frame(width: 18, height: 8)
            }
            Text("高")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

@MainActor
private struct TypingStatsKeyboardHeatmap: View, Equatable {
    let counts: [UInt16: Int64]
    let maximumCount: Int64
    let exposesEmptyKeyMetadata: Bool

    var body: some View {
        FittedTypingStatsKeyboard(
            counts: counts,
            maximumCount: maximumCount,
            exposesEmptyKeyMetadata: exposesEmptyKeyMetadata
        )
    }
}

private struct TypingStatsKeyboardCanvasEntry: Identifiable, Hashable {
    let renderedKey: MacKeyboardRenderedKey
    let frame: CGRect

    var id: String { renderedKey.id }
}

private enum TypingStatsKeyboardCanvasLayout {
    static let baseMetrics = MacKeyboardLayoutMetrics.typingStats
    static let baseSize = baseMetrics.canvasSize(for: TypingStatsKeyboardPresentation.visualLayout)
    static let entries: [TypingStatsKeyboardCanvasEntry] = {
        let descriptorsByID = Dictionary(
            uniqueKeysWithValues: TypingStatsKeyboardPresentation.layout.keys.map { ($0.id, $0) }
        )
        return TypingStatsKeyboardPresentation.visualLayout.placements.map { placement in
            let descriptor = placement.content.keyID.flatMap { descriptorsByID[$0] }
            return TypingStatsKeyboardCanvasEntry(
                renderedKey: MacKeyboardRenderedKey(
                    placement: placement,
                    descriptor: descriptor
                ),
                frame: baseMetrics.frame(for: placement)
            )
        }
    }()
}

@MainActor
private struct TypingStatsKeyboardExtendedSection: View, Equatable {
    let counts: [UInt16: Int64]
    let maximumCount: Int64
    let otherKeys: [KeyboardKeyDescriptor]
    let exposesEmptyMetadata: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !TypingStatsKeyboardPresentation.unplacedLayoutKeys.isEmpty {
                Text("额外修饰键")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(TypingStatsKeyboardPresentation.unplacedLayoutKeys) { key in
                        TypingStatsKeycap(
                            key: key,
                            count: counts[key.keyCode, default: 0],
                            maximumCount: maximumCount,
                            exposesEmptyMetadata: exposesEmptyMetadata
                        )
                    }
                }
            }

            Text("导航、功能、数字键盘与国际键")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            ForEach(TypingStatsKeyboardPresentation.extendedRows) { row in
                HStack(spacing: 4) {
                    ForEach(row.keys) { key in
                        TypingStatsKeycap(
                            key: key,
                            count: counts[key.keyCode, default: 0],
                            maximumCount: maximumCount,
                            exposesEmptyMetadata: exposesEmptyMetadata
                        )
                    }
                }
            }

            if !otherKeys.isEmpty {
                Text("其他已识别键")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                HStack(spacing: 4) {
                    ForEach(otherKeys) { key in
                        TypingStatsKeycap(
                            key: key,
                            count: counts[key.keyCode, default: 0],
                            maximumCount: maximumCount,
                            exposesEmptyMetadata: exposesEmptyMetadata
                        )
                    }
                }
            }
        }
    }
}

@MainActor
private struct FittedTypingStatsKeyboard: View {
    @Environment(\.colorScheme) private var colorScheme

    let counts: [UInt16: Int64]
    let maximumCount: Int64
    let exposesEmptyKeyMetadata: Bool

    var body: some View {
        let baseSize = TypingStatsKeyboardCanvasLayout.baseSize

        GeometryReader { proxy in
            let scale = max(0.1, proxy.size.width / baseSize.width)
            let scaledSize = CGSize(
                width: baseSize.width * scale,
                height: baseSize.height * scale
            )
            let interactiveEntries = TypingStatsKeyboardCanvasLayout.entries.filter {
                keyCount(for: $0) > 0 || exposesEmptyKeyMetadata
            }

            ZStack(alignment: .topLeading) {
                Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) {
                    context,
                    _ in
                    context.scaleBy(x: scale, y: scale)
                    for entry in TypingStatsKeyboardCanvasLayout.entries {
                        draw(entry, in: &context)
                    }
                }
                .frame(width: scaledSize.width, height: scaledSize.height)
                .accessibilityHidden(true)

                ForEach(interactiveEntries) { entry in
                    interactionHitTarget(for: entry, scale: scale)
                }
            }
            .frame(
                width: scaledSize.width,
                height: scaledSize.height,
                alignment: .topLeading
            )
        }
        .aspectRatio(baseSize.width / baseSize.height, contentMode: .fit)
    }

    private func keyCount(for entry: TypingStatsKeyboardCanvasEntry) -> Int64 {
        entry.renderedKey.descriptor.map { counts[$0.keyCode, default: 0] } ?? 0
    }

    @ViewBuilder
    private func interactionHitTarget(
        for entry: TypingStatsKeyboardCanvasEntry,
        scale: CGFloat
    ) -> some View {
        let count = keyCount(for: entry)
        let frame = entry.frame
        let scaledFrame = CGRect(
            x: frame.minX * scale,
            y: frame.minY * scale,
            width: frame.width * scale,
            height: frame.height * scale
        )

        let content = Color.clear
            .frame(width: scaledFrame.width, height: scaledFrame.height)
            .contentShape(Rectangle())
            .position(x: scaledFrame.midX, y: scaledFrame.midY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: entry))
            .accessibilityValue(accessibilityValue(for: entry, count: count))

        if count > 0 {
            content
                .help(helpText(for: entry, count: count))
        } else {
            content
        }
    }

    private func accessibilityLabel(for entry: TypingStatsKeyboardCanvasEntry) -> String {
        if let key = entry.renderedKey.descriptor {
            return key.label
        }
        return "锁定或 Touch ID 键"
    }

    private func accessibilityValue(
        for entry: TypingStatsKeyboardCanvasEntry,
        count: Int64
    ) -> String {
        if entry.renderedKey.descriptor != nil {
            return "\(count) 次"
        }
        return "系统不提供普通按键计数"
    }

    private func helpText(
        for entry: TypingStatsKeyboardCanvasEntry,
        count: Int64
    ) -> String {
        if let key = entry.renderedKey.descriptor {
            return "\(key.label)：\(statsCount(count)) 次"
        }
        return "锁定或 Touch ID 键：系统不提供普通按键事件"
    }

    private func draw(
        _ entry: TypingStatsKeyboardCanvasEntry,
        in context: inout GraphicsContext
    ) {
        let count = keyCount(for: entry)
        let frame = entry.frame
        let keyPath = Path(roundedRect: frame, cornerRadius: 7, style: .continuous)

        if count > 0 {
            let shadowPath = Path(
                roundedRect: frame.offsetBy(dx: 0, dy: 1),
                cornerRadius: 7,
                style: .continuous
            )
            context.fill(shadowPath, with: .color(.black.opacity(0.055)))
        }

        context.fill(keyPath, with: .color(BattutaVisualStyle.surface))
        context.fill(keyPath, with: .color(keycapTint(for: count)))
        context.stroke(keyPath, with: .color(strokeColor(for: count)), lineWidth: 1)

        if let key = entry.renderedKey.descriptor {
            drawKeyText(key: key, count: count, in: frame, context: &context)
        } else {
            drawDecoration(entry.renderedKey, in: frame, context: &context)
        }
    }

    private func drawKeyText(
        key: KeyboardKeyDescriptor,
        count: Int64,
        in frame: CGRect,
        context: inout GraphicsContext
    ) {
        let foreground = keycapForeground(for: count)
        let countColor = count > 0 ? foreground : Color.secondary.opacity(0.48)

        if frame.height < 30 {
            drawResolvedText(
                Text(key.label).font(key.widthUnits > 1.2 ? .caption2 : .caption),
                color: foreground,
                at: CGPoint(x: frame.minX + 3, y: frame.midY),
                anchor: .leading,
                in: &context
            )
            drawResolvedText(
                Text(statsCompactKeyCount(count))
                    .font(.caption2.weight(count > 0 ? .semibold : .regular))
                    .monospacedDigit(),
                color: countColor,
                at: CGPoint(x: frame.maxX - 3, y: frame.midY),
                anchor: .trailing,
                in: &context
            )
        } else {
            drawResolvedText(
                Text(key.label).font(key.widthUnits > 1.2 ? .caption2 : .caption),
                color: foreground,
                at: CGPoint(x: frame.midX, y: frame.midY - 7),
                anchor: .center,
                in: &context
            )
            drawResolvedText(
                Text(statsCompactKeyCount(count))
                    .font(.caption2.weight(count > 0 ? .semibold : .regular))
                    .monospacedDigit(),
                color: countColor,
                at: CGPoint(x: frame.midX, y: frame.midY + 8),
                anchor: .center,
                in: &context
            )
        }
    }

    private func drawDecoration(
        _ renderedKey: MacKeyboardRenderedKey,
        in frame: CGRect,
        context: inout GraphicsContext
    ) {
        if let systemImage = renderedKey.systemImage {
            drawResolvedText(
                Text(Image(systemName: systemImage)).font(.caption),
                color: .primary,
                at: CGPoint(x: frame.midX, y: frame.midY - 6),
                anchor: .center,
                in: &context
            )
        } else {
            drawResolvedText(
                Text(renderedKey.label).font(.caption2),
                color: .primary,
                at: CGPoint(x: frame.midX, y: frame.midY - 6),
                anchor: .center,
                in: &context
            )
        }

        drawResolvedText(
            Text("—").font(.caption2),
            color: Color.secondary.opacity(0.55),
            at: CGPoint(x: frame.midX, y: frame.midY + 8),
            anchor: .center,
            in: &context
        )
    }

    private func drawResolvedText(
        _ text: Text,
        color: Color,
        at point: CGPoint,
        anchor: UnitPoint,
        in context: inout GraphicsContext
    ) {
        var resolved = context.resolve(text)
        resolved.shading = .color(color)
        context.draw(resolved, at: point, anchor: anchor)
    }

    private func keycapTint(for count: Int64) -> Color {
        guard count > 0 else { return .clear }
        return BattutaVisualStyle.accent.opacity(0.10 + keycapIntensity(for: count) * 0.46)
    }

    private func strokeColor(for count: Int64) -> Color {
        guard count > 0 else { return BattutaVisualStyle.separator.opacity(0.55) }
        return BattutaVisualStyle.accent.opacity(0.26 + keycapIntensity(for: count) * 0.34)
    }

    private func keycapForeground(for count: Int64) -> Color {
        guard count > 0 else { return .primary }
        return colorScheme == .dark
            ? .white.opacity(0.92)
            : .black.opacity(0.84)
    }

    private func keycapIntensity(for count: Int64) -> Double {
        guard count > 0, maximumCount > 0 else { return 0 }
        return log(Double(count) + 1) / log(Double(maximumCount) + 1)
    }
}

@MainActor
private struct TypingStatsKeycap: View {
    @Environment(\.colorScheme) private var colorScheme

    let key: KeyboardKeyDescriptor
    let count: Int64
    let maximumCount: Int64
    let size: CGSize?
    let exposesEmptyMetadata: Bool

    init(
        key: KeyboardKeyDescriptor,
        count: Int64,
        maximumCount: Int64,
        size: CGSize? = nil,
        exposesEmptyMetadata: Bool = false
    ) {
        self.key = key
        self.count = count
        self.maximumCount = maximumCount
        self.size = size
        self.exposesEmptyMetadata = exposesEmptyMetadata
    }

    private var width: CGFloat {
        max(38, CGFloat(key.widthUnits) * 38 + CGFloat(max(0, key.widthUnits - 1)) * 4)
    }

    private var resolvedSize: CGSize {
        size ?? CGSize(width: width, height: 50)
    }

    private var intensity: Double {
        guard count > 0, maximumCount > 0 else { return 0 }
        return log(Double(count) + 1) / log(Double(maximumCount) + 1)
    }

    var body: some View {
        let content = Group {
            if resolvedSize.height < 30 {
                HStack(spacing: 3) {
                    keyLabel
                    keyCount
                }
                .padding(.horizontal, 3)
            } else {
                VStack(spacing: 3) {
                    keyLabel
                    keyCount
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(
            width: resolvedSize.width,
            height: resolvedSize.height
        )
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(BattutaVisualStyle.surface)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(keycapTint)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    count > 0
                        ? BattutaVisualStyle.accent.opacity(0.26 + intensity * 0.34)
                        : BattutaVisualStyle.separator.opacity(0.55)
                )
        )
        .shadow(
            color: .black.opacity(count > 0 ? 0.055 : 0),
            radius: count > 0 ? 1 : 0,
            y: count > 0 ? 1 : 0
        )

        return Group {
            if count > 0 {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(key.label)
                    .accessibilityValue("\(count) 次")
                    .help("\(key.label)：\(statsCount(count)) 次")
            } else if exposesEmptyMetadata {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(key.label)
                    .accessibilityValue("0 次")
            } else {
                content.accessibilityHidden(true)
            }
        }
    }

    private var keyLabel: some View {
        Text(key.label)
            .font(key.widthUnits > 1.2 ? .caption2 : .caption)
            .foregroundStyle(keycapForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var keyCount: some View {
        Text(statsCompactKeyCount(count))
            .font(.caption2.weight(count > 0 ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(count > 0 ? keycapForeground : Color.secondary.opacity(0.48))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
    }

    private var keycapTint: Color {
        guard count > 0 else { return .clear }
        return BattutaVisualStyle.accent.opacity(0.10 + intensity * 0.46)
    }

    private var keycapForeground: Color {
        guard count > 0 else { return .primary }
        return colorScheme == .dark
            ? .white.opacity(0.92)
            : .black.opacity(0.84)
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
