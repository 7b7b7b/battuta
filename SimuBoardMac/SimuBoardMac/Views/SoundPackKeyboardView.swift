import SwiftUI

enum SoundPackKeyboardPalette {
    static func color(for row: KeyboardRowID) -> Color {
        switch row {
        case .r0: .orange
        case .r1: .cyan
        case .r2: .green
        case .r3: .purple
        case .r4: .gray
        }
    }
}

@MainActor
struct SoundPackKeyboardView: View {
    @ObservedObject var editor: SoundPackEditorModel

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(editor.layout.rows) { row in
                    HStack(spacing: 4) {
                        ForEach(row.keys) { key in
                            SoundPackKeycap(editor: editor, key: key)
                        }
                    }
                    .padding(.bottom, row.id == "function" ? 8 : 0)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color(nsColor: .windowBackgroundColor),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

@MainActor
private struct SoundPackKeycap: View {
    @ObservedObject var editor: SoundPackEditorModel
    let key: KeyboardKeyDescriptor
    @State private var isPointerDown = false

    private var isSelected: Bool { editor.selectedKeyID == key.id }
    private var hasOverride: Bool {
        editor.overrideChoice(for: key.id, phase: .press) != .inherit
            || editor.overrideChoice(for: key.id, phase: .release) != .inherit
    }

    private var width: CGFloat {
        max(34, CGFloat(key.widthUnits) * 34 + CGFloat(max(0, key.widthUnits - 1)) * 4)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(keycapFill)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(keycapStroke, lineWidth: isSelected ? 2 : 1)

            Text(key.label)
                .font(key.widthUnits > 1.2 ? .caption2 : .caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(key.isAssignable ? .primary : .tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if hasOverride {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .padding(5)
            }
        }
        .frame(width: width, height: key.row == .r4 && key.label.hasPrefix("F") ? 32 : 38)
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

    private var keycapFill: Color {
        if !key.isAssignable { return Color.secondary.opacity(0.06) }
        if isPointerDown { return rowColor.opacity(0.30) }
        if isSelected { return rowColor.opacity(0.20) }
        switch editor.mappingMode {
        case .generic:
            return Color.secondary.opacity(0.10)
        case .recommended:
            return rowColor.opacity(0.11)
        case .perKey:
            return hasOverride ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)
        }
    }

    private var keycapStroke: Color {
        if isSelected { return Color.accentColor }
        if editor.mappingMode == .recommended { return rowColor.opacity(0.48) }
        return Color.secondary.opacity(0.28)
    }

    private var rowColor: Color {
        SoundPackKeyboardPalette.color(for: key.row)
    }
}
