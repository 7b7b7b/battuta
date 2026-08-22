import Foundation

enum SwitchProfile: String, CaseIterable, Identifiable, Sendable {
    case holyPanda = "holypanda"
    case mxBrown = "mxbrown"
    case mxBlue = "mxblue"
    case boxNavy = "boxnavy"
    case blueAlps = "bluealps"
    case cream
    case alpaca
    case blackInk = "blackink"
    case redInk = "redink"
    case mxBlack = "mxblack"
    case turquoise
    case topre
    case buckling

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .holyPanda: "Holy Panda"
        case .mxBrown: "Cherry MX Brown"
        case .mxBlue: "Cherry MX Blue"
        case .boxNavy: "Kailh BOX Navy"
        case .blueAlps: "SKCM Blue Alps"
        case .cream: "NovelKeys Cream"
        case .alpaca: "Alpaca"
        case .blackInk: "Gateron Black Ink"
        case .redInk: "Gateron Red Ink"
        case .mxBlack: "Cherry MX Black"
        case .turquoise: "Turquoise Tealios"
        case .topre: "Topre"
        case .buckling: "IBM Buckling Spring"
        }
    }

    var family: String {
        switch self {
        case .holyPanda, .mxBrown: "段落"
        case .mxBlue, .boxNavy, .blueAlps: "点击"
        case .cream, .alpaca, .blackInk, .redInk, .mxBlack, .turquoise: "线性"
        case .topre: "静电容"
        case .buckling: "屈曲弹簧"
        }
    }

    var tone: String {
        switch self {
        case .holyPanda: "饱满、集中"
        case .mxBrown: "温和、均衡"
        case .mxBlue: "清脆、经典"
        case .boxNavy: "厚重、响亮"
        case .blueAlps: "复古、锐利"
        case .cream: "顺滑、奶油"
        case .alpaca: "干净、柔和"
        case .blackInk: "低沉、扎实"
        case .redInk: "轻快、圆润"
        case .mxBlack: "沉稳、硬朗"
        case .turquoise: "明亮、顺滑"
        case .topre: "柔韧、闷响"
        case .buckling: "复古、金属感"
        }
    }

    var usesOnlyGenericSamples: Bool { self == .mxBlue }
}
