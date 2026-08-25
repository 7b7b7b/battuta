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

private struct MacKeyboardLayoutRenderEntry: Identifiable {
    let renderedKey: MacKeyboardRenderedKey
    let frame: CGRect

    var id: String { renderedKey.id }
}

private struct MacKeyboardLayoutRenderPlan {
    let canvasSize: CGSize
    let entries: [MacKeyboardLayoutRenderEntry]
}

@MainActor
private enum MacKeyboardLayoutRenderPlanCache {
    struct CacheKey: Hashable {
        let layoutID: String
        let visualLayoutID: String
        let metrics: MacKeyboardLayoutMetrics
    }

    private static var plans: [CacheKey: MacKeyboardLayoutRenderPlan] = [:]

    static func plan(
        keyboardLayout: KeyboardLayout,
        visualLayout: KeyboardVisualLayout,
        metrics: MacKeyboardLayoutMetrics
    ) -> MacKeyboardLayoutRenderPlan {
        let cacheKey = CacheKey(
            layoutID: keyboardLayout.id,
            visualLayoutID: visualLayout.id,
            metrics: metrics
        )
        if let cached = plans[cacheKey] {
            return cached
        }

        let descriptorsByID = Dictionary(uniqueKeysWithValues: keyboardLayout.keys.map { ($0.id, $0) })
        let plan = MacKeyboardLayoutRenderPlan(
            canvasSize: metrics.canvasSize(for: visualLayout),
            entries: visualLayout.placements.map { placement in
                let descriptor = placement.content.keyID.flatMap { descriptorsByID[$0] }
                return MacKeyboardLayoutRenderEntry(
                    renderedKey: MacKeyboardRenderedKey(
                        placement: placement,
                        descriptor: descriptor
                    ),
                    frame: metrics.frame(for: placement)
                )
            }
        )
        plans[cacheKey] = plan
        return plan
    }
}

@MainActor
struct MacKeyboardLayoutView<Keycap: View>: View {
    private let renderPlan: MacKeyboardLayoutRenderPlan
    private let keycap: (MacKeyboardRenderedKey, CGSize) -> Keycap

    init(
        keyboardLayout: KeyboardLayout,
        visualLayout: KeyboardVisualLayout = KeyboardVisualLayoutCatalog.magicKeyboardANSI,
        metrics: MacKeyboardLayoutMetrics,
        @ViewBuilder keycap: @escaping (MacKeyboardRenderedKey, CGSize) -> Keycap
    ) {
        renderPlan = MacKeyboardLayoutRenderPlanCache.plan(
            keyboardLayout: keyboardLayout,
            visualLayout: visualLayout,
            metrics: metrics
        )
        self.keycap = keycap
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(renderPlan.entries) { entry in
                keycap(entry.renderedKey, entry.frame.size)
                    .frame(width: entry.frame.width, height: entry.frame.height)
                    .position(x: entry.frame.midX, y: entry.frame.midY)
            }
        }
        .frame(
            width: renderPlan.canvasSize.width,
            height: renderPlan.canvasSize.height,
            alignment: .topLeading
        )
    }
}
