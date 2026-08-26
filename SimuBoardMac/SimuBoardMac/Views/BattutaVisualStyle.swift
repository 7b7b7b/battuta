import AppKit
import SwiftUI

/// Shared visual language for Battuta's menu, statistics and editor surfaces.
/// System semantic colors keep the hierarchy legible in both light and dark mode;
/// the lime accent is reserved for state, selection and the primary action.
enum BattutaVisualStyle {
    static let accent = Color(red: 0.72, green: 0.91, blue: 0.30)
    static let accentStrong = Color(nsColor: NSColor(name: "BattutaAccentStrong") { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.57, green: 0.79, blue: 0.17, alpha: 1)
            : NSColor(srgbRed: 0.27, green: 0.43, blue: 0.04, alpha: 1)
    })
    /// Darker than the decorative lime so white control labels remain legible.
    static let actionAccent = Color(nsColor: NSColor(name: "BattutaActionAccent") { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.29, green: 0.48, blue: 0.04, alpha: 1)
            : NSColor(srgbRed: 0.28, green: 0.47, blue: 0.04, alpha: 1)
    })
    static let accentSoft = accent.opacity(0.13)
    static let cyan = Color(red: 0.25, green: 0.72, blue: 0.82)
    static let violet = Color(red: 0.60, green: 0.50, blue: 0.92)
    static let amber = Color(red: 0.95, green: 0.67, blue: 0.20)

    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let recessed = Color(nsColor: .underPageBackgroundColor)
    static let surface = Color(nsColor: NSColor.controlBackgroundColor.withAlphaComponent(1))
    static let separator = Color(nsColor: .separatorColor)

    /// Dense, high-contrast surface used by the statistics instrument cards.
    /// It intentionally stays dark in both appearances so the eul-inspired
    /// hierarchy remains stable against Battuta's translucent window canvas.
    static let instrumentSurface = Color(nsColor: NSColor(name: "BattutaInstrumentSurface") { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.025, green: 0.030, blue: 0.026, alpha: 0.98)
            : NSColor(srgbRed: 0.045, green: 0.050, blue: 0.045, alpha: 0.96)
    })
    static let instrumentPrimary = Color.white.opacity(0.94)
    static let instrumentSecondary = Color.white.opacity(0.58)
    static let instrumentSeparator = Color.white.opacity(0.12)

    static let cardRadius: CGFloat = 14
    static let compactRadius: CGFloat = 10
    static let pagePadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    /// Empty window regions keep only a light semantic tint; the AppKit visual
    /// effect below supplies the behind-window blur.
    static let glassTintOpacity = 0.14
}

/// Heatmap colors keep Battuta's original lime/cyan visual language while the
/// statistics model supplies the adaptive, continuous value distribution.
enum BattutaHeatmapPalette {
    static var sequentialGradient: LinearGradient {
        gradient([
            (BattutaVisualStyle.accent.opacity(0.10), 0.00),
            (BattutaVisualStyle.accent.opacity(0.25), 0.33),
            (BattutaVisualStyle.accent.opacity(0.40), 0.67),
            (BattutaVisualStyle.accent.opacity(0.56), 1.00),
        ])
    }

    static var yearGradient: LinearGradient {
        gradient([
            (BattutaVisualStyle.accent.opacity(0.24), 0.00),
            (BattutaVisualStyle.accent.opacity(0.42), 0.33),
            (BattutaVisualStyle.accent.opacity(0.66), 0.67),
            (BattutaVisualStyle.accent.opacity(0.92), 1.00),
        ])
    }

    static var timelineGradient: LinearGradient {
        gradient([
            (BattutaVisualStyle.cyan.opacity(0.28), 0.00),
            (BattutaVisualStyle.cyan.opacity(0.55), 0.33),
            (BattutaVisualStyle.accent.opacity(0.72), 0.67),
            (BattutaVisualStyle.accentStrong, 1.00),
        ])
    }

    static var rhythmGradient: LinearGradient {
        gradient([
            (BattutaVisualStyle.accent.opacity(0.16), 0.00),
            (BattutaVisualStyle.accent.opacity(0.76), 1.00),
        ])
    }

    static var divergingGradient: LinearGradient {
        gradient([
            (BattutaVisualStyle.cyan.opacity(0.72), 0.00),
            (BattutaVisualStyle.cyan.opacity(0.14), 0.45),
            (Color.white.opacity(0.08), 0.50),
            (BattutaVisualStyle.accent.opacity(0.14), 0.55),
            (BattutaVisualStyle.accent.opacity(0.76), 1.00),
        ])
    }

    static func keyboardFillColor(at normalizedValue: Double) -> Color {
        BattutaVisualStyle.accent.opacity(0.10 + normalized(normalizedValue) * 0.46)
    }

    static func keyboardStrokeColor(at normalizedValue: Double) -> Color {
        BattutaVisualStyle.accent.opacity(0.26 + normalized(normalizedValue) * 0.34)
    }

    static func yearColor(at normalizedValue: Double) -> Color {
        BattutaVisualStyle.accent.opacity(0.24 + normalized(normalizedValue) * 0.68)
    }

    static func timelineColor(at normalizedValue: Double) -> Color {
        let intensity = normalized(normalizedValue)
        if intensity < 0.25 {
            return BattutaVisualStyle.cyan.opacity(0.28)
        }
        if intensity < 0.55 {
            return BattutaVisualStyle.cyan.opacity(0.55)
        }
        if intensity < 0.82 {
            return BattutaVisualStyle.accent.opacity(0.72)
        }
        return BattutaVisualStyle.accentStrong
    }

    static func rhythmColor(at normalizedValue: Double) -> Color {
        BattutaVisualStyle.accent.opacity(0.16 + normalized(normalizedValue) * 0.60)
    }

    /// Accepts the symmetric -1...1 value produced by
    /// `TypingDivergingHeatmapScale.normalized(_:)`.
    static func divergingColor(at normalizedValue: Double) -> Color {
        let value = min(1, max(-1, normalizedValue))
        if value < 0 {
            return BattutaVisualStyle.cyan.opacity(0.14 + abs(value) * 0.58)
        }
        if value > 0 {
            return BattutaVisualStyle.accent.opacity(0.14 + value * 0.62)
        }
        return Color.white.opacity(0.08)
    }

    private static func gradient(_ stops: [(Color, CGFloat)]) -> LinearGradient {
        LinearGradient(
            stops: stops.map { color, location in
                Gradient.Stop(color: color, location: location)
            },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private static func normalized(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

enum BattutaHeatmapLegendPalette {
    case keyboard
    case year
    case timeline
    case rhythm
    case diverging
}

struct BattutaHeatmapLegend: View {
    let leadingLabel: String
    let trailingLabel: String
    var palette: BattutaHeatmapLegendPalette = .keyboard
    var barWidth: CGFloat = 112
    var labelColor: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Text(leadingLabel)
                .monospacedDigit()

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(gradient)
                .frame(width: barWidth, height: 9)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                }

            Text(trailingLabel)
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(labelColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var gradient: LinearGradient {
        switch palette {
        case .keyboard:
            return BattutaHeatmapPalette.sequentialGradient
        case .year:
            return BattutaHeatmapPalette.yearGradient
        case .timeline:
            return BattutaHeatmapPalette.timelineGradient
        case .rhythm:
            return BattutaHeatmapPalette.rhythmGradient
        case .diverging:
            return BattutaHeatmapPalette.divergingGradient
        }
    }

    private var accessibilityText: String {
        switch palette {
        case .keyboard, .year, .timeline, .rhythm:
            "连续颜色图例，从 \(leadingLabel) 到 \(trailingLabel)"
        case .diverging:
            "连续差异颜色图例，从 \(leadingLabel)，经过零，到 \(trailingLabel)"
        }
    }
}

/// Immediate, app-drawn heatmap detail. This avoids AppKit's intentionally
/// delayed `.help` tooltip while still communicating a click-locked state.
struct BattutaHeatmapTooltip: View {
    let text: String
    let isPinned: Bool
    var maxWidth: CGFloat = 280

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BattutaVisualStyle.accent)
            }
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(BattutaVisualStyle.instrumentPrimary)
                .monospacedDigit()
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(
            BattutaVisualStyle.instrumentSurface,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isPinned
                        ? BattutaVisualStyle.accent.opacity(0.55)
                        : Color.white.opacity(0.18),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.black.opacity(0.30), radius: 8, y: 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct BattutaWindowGlass: View {
    var body: some View {
        Rectangle()
            .fill(BattutaVisualStyle.canvas.opacity(BattutaVisualStyle.glassTintOpacity))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// AppKit owns the actual backdrop sampling. SwiftUI materials can otherwise
/// resolve as an almost-opaque in-window layer and only leave the titlebar clear.
@MainActor
final class BattutaGlassHostingController<Content: View>: NSViewController {
    private let hostingController: NSHostingController<Content>

    init(rootView: Content) {
        hostingController = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let backdrop = NSVisualEffectView()
        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.isEmphasized = false

        let hostedView = hostingController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.wantsLayer = true
        hostedView.layer?.backgroundColor = NSColor.clear.cgColor

        view = backdrop
        addChild(hostingController)
        backdrop.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: backdrop.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
        ])
    }
}

@MainActor
enum BattutaWindowChrome {
    static func apply(to window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .line
    }
}

private struct BattutaBehindWindowEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .underWindowBackground
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

private final class BattutaWindowAccessorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        Task { @MainActor in
            BattutaWindowChrome.apply(to: window)
        }
    }
}

private struct BattutaWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        BattutaWindowAccessorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct BattutaPanelModifier: ViewModifier {
    let radius: CGFloat
    let emphasized: Bool

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(BattutaVisualStyle.surface)
                    if emphasized {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(BattutaVisualStyle.accentSoft)
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        emphasized
                            ? BattutaVisualStyle.accent.opacity(0.28)
                            : BattutaVisualStyle.separator.opacity(0.72),
                        lineWidth: 1
                    )
            }
    }
}

private struct BattutaTintedPanelModifier: ViewModifier {
    let tint: Color
    let tintOpacity: Double
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(BattutaVisualStyle.surface)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(tint.opacity(tintOpacity))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
    }
}

extension View {
    func battutaPanel(
        radius: CGFloat = BattutaVisualStyle.cardRadius,
        emphasized: Bool = false
    ) -> some View {
        modifier(BattutaPanelModifier(radius: radius, emphasized: emphasized))
    }

    func battutaTintedPanel(
        _ tint: Color,
        opacity: Double = 0.08,
        radius: CGFloat = BattutaVisualStyle.compactRadius
    ) -> some View {
        modifier(
            BattutaTintedPanelModifier(
                tint: tint,
                tintOpacity: opacity,
                radius: radius
            )
        )
    }

    func battutaWindowGlass(providesBackdrop: Bool = false) -> some View {
        background {
            ZStack {
                if providesBackdrop {
                    BattutaBehindWindowEffect()
                }
                BattutaWindowGlass()
            }
            .ignoresSafeArea()
        }
    }

    func battutaConfigureContainingWindow() -> some View {
        background(BattutaWindowAccessor().frame(width: 0, height: 0))
    }
}

struct BattutaIconTile: View {
    let symbol: String
    var tint: Color = BattutaVisualStyle.accent
    var size: CGFloat = 38
    var symbolSize: CGFloat = 16

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(tint.opacity(0.18))
            }
    }
}

/// Uses the icon embedded in the running app bundle so the UI always stays in
/// sync when Battuta's App Icon asset changes.
struct BattutaApplicationIcon: View {
    var size: CGFloat = 40

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Battuta 应用图标")
    }
}

struct BattutaStatusPill: View {
    let title: String
    let symbol: String
    var tint: Color = BattutaVisualStyle.accentStrong

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.11), in: Capsule())
            .overlay {
                Capsule().stroke(tint.opacity(0.16))
            }
    }
}

struct BattutaSectionHeading: View {
    let title: String
    let subtitle: String?
    let symbol: String?

    init(_ title: String, subtitle: String? = nil, symbol: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BattutaVisualStyle.accentStrong)
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct BattutaCardLabel: View {
    let title: String
    let symbol: String
    var tint: Color = BattutaVisualStyle.accentStrong

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
    }
}
