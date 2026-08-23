import SwiftUI

struct MacKeyboardLayoutMetrics: Hashable, Sendable {
    let horizontalPitch: CGFloat
    let keyGap: CGFloat
    let keyHeight: CGFloat
    let rowGap: CGFloat
    let splitArrowGap: CGFloat

    static let typingStats = MacKeyboardLayoutMetrics(
        horizontalPitch: 48,
        keyGap: 5,
        keyHeight: 42,
        rowGap: 6,
        splitArrowGap: 3
    )

    static let soundPackEditor = MacKeyboardLayoutMetrics(
        horizontalPitch: 38,
        keyGap: 4,
        keyHeight: 32,
        rowGap: 5,
        splitArrowGap: 2
    )

    func canvasSize(for layout: KeyboardVisualLayout) -> CGSize {
        CGSize(
            width: CGFloat(layout.widthUnits) * horizontalPitch - keyGap,
            height: CGFloat(layout.rowCount) * keyHeight
                + CGFloat(max(0, layout.rowCount - 1)) * rowGap
        )
    }

    func frame(for placement: KeyboardVisualPlacement) -> CGRect {
        let x = CGFloat(placement.xUnits) * horizontalPitch
        let width = CGFloat(placement.widthUnits) * horizontalPitch - keyGap
        let rowY = CGFloat(placement.row) * (keyHeight + rowGap)

        switch placement.verticalSlot {
        case .full:
            return CGRect(x: x, y: rowY, width: width, height: keyHeight)
        case .upperHalf:
            return CGRect(
                x: x,
                y: rowY,
                width: width,
                height: (keyHeight - splitArrowGap) / 2
            )
        case .lowerHalf:
            let height = (keyHeight - splitArrowGap) / 2
            return CGRect(
                x: x,
                y: rowY + height + splitArrowGap,
                width: width,
                height: height
            )
        }
    }
}

struct MacKeyboardRenderedKey: Identifiable, Hashable {
    let placement: KeyboardVisualPlacement
    let descriptor: KeyboardKeyDescriptor?

    var id: String { placement.id }
    var label: String { descriptor?.label ?? placement.content.fallbackLabel }
    var systemImage: String? { placement.content.systemImage }
    var isDecorative: Bool { descriptor == nil }
}

@MainActor
struct MacKeyboardLayoutView<Keycap: View>: View {
    let keyboardLayout: KeyboardLayout
    let visualLayout: KeyboardVisualLayout
    let metrics: MacKeyboardLayoutMetrics
    private let keycap: (MacKeyboardRenderedKey, CGSize) -> Keycap

    init(
        keyboardLayout: KeyboardLayout,
        visualLayout: KeyboardVisualLayout = KeyboardVisualLayoutCatalog.magicKeyboardANSI,
        metrics: MacKeyboardLayoutMetrics,
        @ViewBuilder keycap: @escaping (MacKeyboardRenderedKey, CGSize) -> Keycap
    ) {
        self.keyboardLayout = keyboardLayout
        self.visualLayout = visualLayout
        self.metrics = metrics
        self.keycap = keycap
    }

    private var descriptorsByID: [KeyboardKeyID: KeyboardKeyDescriptor] {
        Dictionary(uniqueKeysWithValues: keyboardLayout.keys.map { ($0.id, $0) })
    }

    var body: some View {
        let descriptorsByID = descriptorsByID
        let canvasSize = metrics.canvasSize(for: visualLayout)

        ZStack(alignment: .topLeading) {
            ForEach(visualLayout.placements) { placement in
                let descriptor = placement.content.keyID.flatMap { descriptorsByID[$0] }
                let renderedKey = MacKeyboardRenderedKey(
                    placement: placement,
                    descriptor: descriptor
                )
                let frame = metrics.frame(for: placement)

                keycap(renderedKey, frame.size)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }
}
