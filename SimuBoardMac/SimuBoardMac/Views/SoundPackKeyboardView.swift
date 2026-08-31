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
private enum SoundPackExtendedKeyboardRows {
    private static let rowsByID = Dictionary(
        uniqueKeysWithValues: KeyboardExtendedLayoutCatalog.rows.map { ($0.id, $0.keys) }
    )

    static let navigation = rowsByID["extended.navigation"] ?? []
    static let functionKeys = rowsByID["extended.extendedFunction"] ?? []
    static let keypadRows = [
        rowsByID["extended.keypadTop"] ?? [],
        rowsByID["extended.keypadUpper"] ?? [],
        rowsByID["extended.keypadMiddle"] ?? [],
        rowsByID["extended.keypadLower"] ?? [],
        rowsByID["extended.keypadBottom"] ?? [],
    ]
    static let internationalAndMedia =
        (rowsByID["extended.international"] ?? [])
        + (rowsByID["extended.media"] ?? [])
}

private struct SoundPackKeyboardPresentation: Equatable {
    private static let visualLayout = KeyboardVisualLayoutCatalog.magicKeyboardANSI
    private static let overrideChoicesToHighlight: Set<SoundPackKeyOverride> = [.silent]

    let editorIdentity: ObjectIdentifier
    let layout: KeyboardLayout
    let mappingMode: SoundPackEditorMappingMode
    let selectedKeyID: KeyboardKeyID
    let overriddenKeyIDs: Set<KeyboardKeyID>
    let unplacedKeys: [KeyboardKeyDescriptor]

    @MainActor
    init(editor: SoundPackEditorModel) {
        editorIdentity = ObjectIdentifier(editor)
        layout = editor.layout
        mappingMode = editor.mappingMode
        selectedKeyID = editor.selectedKeyID
        overriddenKeyIDs = Self.overriddenKeyIDs(in: editor.manifest)
        unplacedKeys = editor.layout.keys.filter { !Self.visualLayout.keyIDs.contains($0.id) }
    }

    func keycapPresentation(
        for key: KeyboardKeyDescriptor,
        size: CGSize? = nil
    ) -> SoundPackKeycapPresentation {
        SoundPackKeycapPresentation(
            key: key,
            size: size,
            isSelected: selectedKeyID == key.id,
            hasOverride: overriddenKeyIDs.contains(key.id),
            mappingMode: mappingMode
        )
    }

    private static func overriddenKeyIDs(
        in manifest: SoundPackManifest?
    ) -> Set<KeyboardKeyID> {
        guard let manifest else { return [] }
        let press = manifest.press.keyOverrides.compactMap { key, value -> KeyboardKeyID? in
            guard shouldHighlightOverride(value) else { return nil }
            return KeyboardKeyID(key)
        }
        let release = manifest.release.keyOverrides.compactMap { key, value -> KeyboardKeyID? in
            guard shouldHighlightOverride(value) else { return nil }
            return KeyboardKeyID(key)
        }
        return Set(press).union(release)
    }

    private static func shouldHighlightOverride(_ value: SoundPackKeyOverride) -> Bool {
        if overrideChoicesToHighlight.contains(value) { return true }
        if case .asset = value { return true }
        return false
    }
}

@MainActor
struct SoundPackKeyboardView: View, Equatable {
    private let presentation: SoundPackKeyboardPresentation
    private let onPressKey: (KeyboardKeyDescriptor) -> Void
    private let onReleaseKey: (KeyboardKeyDescriptor) -> Void

    private let visualLayout = KeyboardVisualLayoutCatalog.magicKeyboardANSI

    init(editor: SoundPackEditorModel) {
        presentation = SoundPackKeyboardPresentation(editor: editor)
        onPressKey = { key in
            editor.selectedKeyID = key.id
            editor.preview(keyCode: key.keyCode, phase: .press)
        }
        onReleaseKey = { key in
            editor.preview(keyCode: key.keyCode, phase: .release)
        }
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.presentation == rhs.presentation
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
                        presentation: presentation,
                        visualLayout: visualLayout,
                        onPressKey: onPressKey,
                        onReleaseKey: onReleaseKey
                    )
                }
                .padding(16)
                .battutaPanel()

                SoundPackExtendedKeyboardSection(
                    presentation: presentation,
                    modifierKeys: presentation.unplacedKeys,
                    onPressKey: onPressKey,
                    onReleaseKey: onReleaseKey
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
    let presentation: SoundPackKeyboardPresentation
    let visualLayout: KeyboardVisualLayout
    let onPressKey: (KeyboardKeyDescriptor) -> Void
    let onReleaseKey: (KeyboardKeyDescriptor) -> Void

    private let baseMetrics = MacKeyboardLayoutMetrics.soundPackEditor

    var body: some View {
        let baseSize = baseMetrics.canvasSize(for: visualLayout)

        GeometryReader { proxy in
            let scale = max(0.1, proxy.size.width / baseSize.width)

            MacKeyboardLayoutView(
                keyboardLayout: presentation.layout,
                visualLayout: visualLayout,
                metrics: baseMetrics
            ) { renderedKey, size in
                if let key = renderedKey.descriptor {
                    SoundPackKeycap(
                        presentation: presentation.keycapPresentation(for: key, size: size),
                        onPressKey: onPressKey,
                        onReleaseKey: onReleaseKey
                    )
                    .equatable()
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
    let presentation: SoundPackKeyboardPresentation
    let modifierKeys: [KeyboardKeyDescriptor]
    let onPressKey: (KeyboardKeyDescriptor) -> Void
    let onReleaseKey: (KeyboardKeyDescriptor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BattutaSectionHeading(
                "外接键盘与扩展键区",
                subtitle: "右侧修饰键、导航、F13–F20、数字键盘与国际键均可独立映射",
                symbol: "keyboard.badge.ellipsis"
            )

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    keyGroup(
                        "修饰与导航",
                        rows: [modifierKeys + SoundPackExtendedKeyboardRows.navigation]
                    )
                    keyGroup(
                        "扩展功能键",
                        rows: [
                            Array(SoundPackExtendedKeyboardRows.functionKeys.prefix(4)),
                            Array(SoundPackExtendedKeyboardRows.functionKeys.dropFirst(4)),
                        ]
                    )
                    keyGroup(
                        "国际与媒体键",
                        rows: SoundPackExtendedKeyboardRows.internationalAndMedia.chunked(maximumCount: 5)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                keyGroup("数字键盘", rows: SoundPackExtendedKeyboardRows.keypadRows)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .battutaPanel()
    }

    private func keyGroup(
        _ title: String,
        rows: [[KeyboardKeyDescriptor]]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, keys in
                HStack(spacing: 4) {
                    ForEach(keys) { key in
                        SoundPackKeycap(
                            presentation: presentation.keycapPresentation(for: key),
                            onPressKey: onPressKey,
                            onReleaseKey: onReleaseKey
                        )
                        .equatable()
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

private struct SoundPackKeycapPresentation: Equatable {
    let key: KeyboardKeyDescriptor
    let size: CGSize?
    let isSelected: Bool
    let hasOverride: Bool
    let mappingMode: SoundPackEditorMappingMode
}

@MainActor
private struct SoundPackKeycap: View, Equatable {
    let presentation: SoundPackKeycapPresentation
    let onPressKey: (KeyboardKeyDescriptor) -> Void
    let onReleaseKey: (KeyboardKeyDescriptor) -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.presentation == rhs.presentation
    }

    var body: some View {
        SoundPackKeycapBody(
            presentation: presentation,
            onPressKey: onPressKey,
            onReleaseKey: onReleaseKey
        )
    }
}

@MainActor
private struct SoundPackKeycapBody: View {
    let presentation: SoundPackKeycapPresentation
    let onPressKey: (KeyboardKeyDescriptor) -> Void
    let onReleaseKey: (KeyboardKeyDescriptor) -> Void
    @State private var isPointerDown = false

    private var key: KeyboardKeyDescriptor { presentation.key }
    private var isSelected: Bool { presentation.isSelected }
    private var hasOverride: Bool { presentation.hasOverride }

    private var width: CGFloat {
        max(34, CGFloat(key.widthUnits) * 34 + CGFloat(max(0, key.widthUnits - 1)) * 4)
    }

    private var resolvedSize: CGSize {
        presentation.size ?? CGSize(width: width, height: 32)
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
        .shadow(
            color: BattutaVisualStyle.keyboardShadow.opacity(isPointerDown ? 0.55 : 1),
            radius: 1,
            y: 1
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard key.isAssignable, !isPointerDown else { return }
                    isPointerDown = true
                    onPressKey(key)
                }
                .onEnded { _ in
                    guard key.isAssignable else { return }
                    if isPointerDown {
                        onReleaseKey(key)
                    }
                    isPointerDown = false
                }
        )
        .animation(.easeOut(duration: 0.08), value: isPointerDown)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(key.label)
        .accessibilityValue(L10n.tr(hasOverride ? "已设置单键覆盖" : "继承映射"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard key.isAssignable else { return }
            onPressKey(key)
            onReleaseKey(key)
        }
    }

    private var keycapTint: Color {
        if !key.isAssignable { return Color.secondary.opacity(0.06) }
        if isPointerDown { return rowColor.opacity(0.30) }
        if isSelected { return rowColor.opacity(0.20) }
        switch presentation.mappingMode {
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
        if presentation.mappingMode == .recommended { return rowColor.opacity(0.26) }
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
        .accessibilityLabel(L10n.tr("锁定或 Touch ID 键"))
        .accessibilityValue(L10n.tr("不可分配音效"))
        .help(L10n.tr("锁定或 Touch ID 键由系统处理，不能作为普通按键分配"))
    }
}
