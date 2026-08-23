import SwiftUI

enum SoundPackKeyboardPalette {
    static func color(for row: KeyboardRowID) -> Color {
        switch row {
        case .r0: BattutaVisualStyle.amber
        case .r1: BattutaVisualStyle.cyan
        case .r2: BattutaVisualStyle.accentStrong
        case .r3: BattutaVisualStyle.violet
        case .r4: .secondary
        }
    }
}

@MainActor
struct SoundPackKeyboardView: View {
    @ObservedObject var editor: SoundPackEditorModel

    private let visualLayout = KeyboardVisualLayoutCatalog.magicKeyboardANSI

    private var unplacedKeys: [KeyboardKeyDescriptor] {
        editor.layout.keys.filter { !visualLayout.keyIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    BattutaSectionHeading(
                        "Apple 紧凑型键盘",
                        subtitle: "US ANSI · 14.5U，点击任意键即可试听或单独设置",
                        symbol: "keyboard"
                    )

                    FittedSoundPackKeyboard(
                        editor: editor,
                        visualLayout: visualLayout
                    )
                }
                .padding(16)
                .battutaPanel()

                SoundPackExtendedKeyboardSection(
                    editor: editor,
                    modifierKeys: unplacedKeys
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color.clear)
    }
}

@MainActor
private struct FittedSoundPackKeyboard: View {
    @ObservedObject var editor: SoundPackEditorModel
    let visualLayout: KeyboardVisualLayout

    private let baseMetrics = MacKeyboardLayoutMetrics.soundPackEditor

    var body: some View {
        let baseSize = baseMetrics.canvasSize(for: visualLayout)

        GeometryReader { proxy in
            let scale = max(0.1, proxy.size.width / baseSize.width)

            MacKeyboardLayoutView(
                keyboardLayout: editor.layout,
                visualLayout: visualLayout,
                metrics: baseMetrics
            ) { renderedKey, size in
                if let key = renderedKey.descriptor {
                    SoundPackKeycap(editor: editor, key: key, size: size)
                } else {
                    SoundPackDecorativeKeycap(renderedKey: renderedKey, size: size)
                }
            }
            .scaleEffect(scale, anchor: .topLeading)
            .frame(
                width: baseSize.width * scale,
                height: baseSize.height * scale,
                alignment: .topLeading
            )
        }
        .aspectRatio(baseSize.width / baseSize.height, contentMode: .fit)
    }
}

@MainActor
private struct SoundPackExtendedKeyboardSection: View {
    @ObservedObject var editor: SoundPackEditorModel
    let modifierKeys: [KeyboardKeyDescriptor]

    private var navigation: [KeyboardKeyDescriptor] { row("navigation") }
    private var functionKeys: [KeyboardKeyDescriptor] { row("extendedFunction") }
    private var keypadRows: [[KeyboardKeyDescriptor]] {
        ["keypadTop", "keypadUpper", "keypadMiddle", "keypadLower", "keypadBottom"]
            .map(row)
    }
    private var internationalAndMedia: [KeyboardKeyDescriptor] {
        row("international") + row("media")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BattutaSectionHeading(
                "外接键盘与扩展键区",
                subtitle: "右侧修饰键、导航、F13–F20、数字键盘与国际键均可独立映射",
                symbol: "keyboard.badge.ellipsis"
            )

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    keyGroup("修饰与导航", rows: [modifierKeys + navigation])
                    keyGroup(
                        "扩展功能键",
                        rows: [
                            Array(functionKeys.prefix(4)),
                            Array(functionKeys.dropFirst(4)),
                        ]
                    )
                    keyGroup(
                        "国际与媒体键",
                        rows: internationalAndMedia.chunked(maximumCount: 5)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                keyGroup("数字键盘", rows: keypadRows)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .battutaPanel()
    }

    private func row(_ id: String) -> [KeyboardKeyDescriptor] {
        KeyboardExtendedLayoutCatalog.rows
            .first(where: { $0.id == "extended.\(id)" })?
            .keys ?? []
    }

    private func keyGroup(
        _ title: String,
        rows: [[KeyboardKeyDescriptor]]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, keys in
                HStack(spacing: 4) {
                    ForEach(keys) { key in
                        SoundPackKeycap(editor: editor, key: key)
                    }
                }
            }
        }
    }
}

private extension Array {
    func chunked(maximumCount: Int) -> [[Element]] {
        guard maximumCount > 0 else { return [self] }
        return stride(from: 0, to: count, by: maximumCount).map { start in
            Array(self[start..<Swift.min(start + maximumCount, count)])
        }
    }
}

@MainActor
private struct SoundPackKeycap: View {
    @ObservedObject var editor: SoundPackEditorModel
    let key: KeyboardKeyDescriptor
    let size: CGSize?
    @State private var isPointerDown = false

    init(
        editor: SoundPackEditorModel,
        key: KeyboardKeyDescriptor,
        size: CGSize? = nil
    ) {
        self.editor = editor
        self.key = key
        self.size = size
    }

    private var isSelected: Bool { editor.selectedKeyID == key.id }
    private var hasOverride: Bool {
        editor.overrideChoice(for: key.id, phase: .press) != .inherit
            || editor.overrideChoice(for: key.id, phase: .release) != .inherit
    }

    private var width: CGFloat {
        max(34, CGFloat(key.widthUnits) * 34 + CGFloat(max(0, key.widthUnits - 1)) * 4)
    }

    private var resolvedSize: CGSize {
        size ?? CGSize(width: width, height: 32)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(BattutaVisualStyle.surface)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(keycapTint)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(keycapStroke, lineWidth: isSelected ? 2 : 1)

            Text(key.label)
                .font(resolvedSize.height < 24 || key.widthUnits > 1.2 ? .caption2 : .caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(key.isAssignable ? .primary : .tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if hasOverride {
                Circle()
                    .fill(BattutaVisualStyle.accentStrong)
                    .frame(width: 6, height: 6)
                    .padding(5)
            }
        }
        .frame(width: resolvedSize.width, height: resolvedSize.height)
        .scaleEffect(isPointerDown ? 0.96 : 1)
        .shadow(color: .black.opacity(isPointerDown ? 0.04 : 0.12), radius: 1, y: 1)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard key.isAssignable, !isPointerDown else { return }
                    isPointerDown = true
                    editor.selectedKeyID = key.id
                    editor.preview(keyCode: key.keyCode, phase: .press)
                }
                .onEnded { _ in
                    guard key.isAssignable else { return }
                    if isPointerDown {
                        editor.preview(keyCode: key.keyCode, phase: .release)
                    }
                    isPointerDown = false
                }
        )
        .animation(.easeOut(duration: 0.08), value: isPointerDown)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(key.label)
        .accessibilityValue(hasOverride ? "已设置单键覆盖" : "继承映射")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard key.isAssignable else { return }
            editor.selectedKeyID = key.id
            editor.preview(keyCode: key.keyCode, phase: .press)
            editor.preview(keyCode: key.keyCode, phase: .release)
        }
    }

    private var keycapTint: Color {
        if !key.isAssignable { return Color.secondary.opacity(0.06) }
        if isPointerDown { return rowColor.opacity(0.30) }
        if isSelected { return rowColor.opacity(0.20) }
        switch editor.mappingMode {
        case .generic:
            return .clear
        case .recommended:
            return rowColor.opacity(0.11)
        case .perKey:
            return hasOverride ? BattutaVisualStyle.accentSoft : .clear
        }
    }

    private var keycapStroke: Color {
        if isSelected { return BattutaVisualStyle.accentStrong }
        if editor.mappingMode == .recommended { return rowColor.opacity(0.26) }
        return BattutaVisualStyle.separator.opacity(0.70)
    }

    private var rowColor: Color {
        SoundPackKeyboardPalette.color(for: key.row)
    }
}

@MainActor
private struct SoundPackDecorativeKeycap: View {
    let renderedKey: MacKeyboardRenderedKey
    let size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(BattutaVisualStyle.surface)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(BattutaVisualStyle.separator.opacity(0.60))

            if let systemImage = renderedKey.systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text(renderedKey.label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("锁定或 Touch ID 键")
        .accessibilityValue("不可分配音效")
        .help("锁定或 Touch ID 键由系统处理，不能作为普通按键分配")
    }
}
