import Foundation

struct KeyboardKeyID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum KeyboardRowID: String, CaseIterable, Codable, Hashable, Sendable {
    case r0 = "R0"
    case r1 = "R1"
    case r2 = "R2"
    case r3 = "R3"
    case r4 = "R4"

    var displayName: String {
        switch self {
        case .r0: "数字行"
        case .r1: "Q 行"
        case .r2: "A 行"
        case .r3: "Z 行"
        case .r4: "其他键"
        }
    }
}

enum KeyboardSpecialKeyID: String, CaseIterable, Codable, Hashable, Sendable {
    case space
    case enter
    case backspace

    var displayName: String {
        switch self {
        case .space: "空格"
        case .enter: "回车"
        case .backspace: "退格"
        }
    }
}

struct KeyboardKeyDescriptor: Identifiable, Codable, Hashable, Sendable {
    let id: KeyboardKeyID
    let keyCode: UInt16
    let label: String
    let row: KeyboardRowID
    let specialKey: KeyboardSpecialKeyID?
    let widthUnits: Double
    let isAssignable: Bool

    init(
        id: KeyboardKeyID,
        keyCode: UInt16,
        label: String,
        row: KeyboardRowID,
        specialKey: KeyboardSpecialKeyID? = nil,
        widthUnits: Double = 1,
        isAssignable: Bool = true
    ) {
        self.id = id
        self.keyCode = keyCode
        self.label = label
        self.row = row
        self.specialKey = specialKey
        self.widthUnits = widthUnits
        self.isAssignable = isAssignable
    }
}

struct KeyboardLayoutRow: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let keys: [KeyboardKeyDescriptor]
}

struct KeyboardLayout: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let displayName: String
    let rows: [KeyboardLayoutRow]

    var keys: [KeyboardKeyDescriptor] { rows.flatMap(\.keys) }
}

enum KeyboardLayoutCatalog {
    static let defaultLayoutID = "mac-ansi-tkl-v1"

    static let ansiTKL = KeyboardLayout(
        id: defaultLayoutID,
        displayName: "Mac ANSI TKL",
        rows: [
            KeyboardLayoutRow(id: "function", keys: [
                key("escape", 53, "esc", .r4),
                key("f1", 122, "F1", .r4), key("f2", 120, "F2", .r4),
                key("f3", 99, "F3", .r4), key("f4", 118, "F4", .r4),
                key("f5", 96, "F5", .r4), key("f6", 97, "F6", .r4),
                key("f7", 98, "F7", .r4), key("f8", 100, "F8", .r4),
                key("f9", 101, "F9", .r4), key("f10", 109, "F10", .r4),
                key("f11", 103, "F11", .r4), key("f12", 111, "F12", .r4),
            ]),
            KeyboardLayoutRow(id: "number", keys: [
                key("backquote", 50, "`", .r0),
                key("digit1", 18, "1", .r0), key("digit2", 19, "2", .r0),
                key("digit3", 20, "3", .r0), key("digit4", 21, "4", .r0),
                key("digit5", 23, "5", .r0), key("digit6", 22, "6", .r0),
                key("digit7", 26, "7", .r0), key("digit8", 28, "8", .r0),
                key("digit9", 25, "9", .r0), key("digit0", 29, "0", .r0),
                key("minus", 27, "-", .r0), key("equal", 24, "=", .r0),
                key("backspace", 51, "delete", .r4, .backspace, 2),
            ]),
            KeyboardLayoutRow(id: "qwerty", keys: [
                key("tab", 48, "tab", .r4, width: 1.5),
                key("q", 12, "Q", .r1), key("w", 13, "W", .r1),
                key("e", 14, "E", .r1), key("r", 15, "R", .r1),
                key("t", 17, "T", .r1), key("y", 16, "Y", .r1),
                key("u", 32, "U", .r1), key("i", 34, "I", .r1),
                key("o", 31, "O", .r1), key("p", 35, "P", .r1),
                key("leftBracket", 33, "[", .r1),
                key("rightBracket", 30, "]", .r1),
                key("backslash", 42, "\\", .r1, width: 1.5),
            ]),
            KeyboardLayoutRow(id: "home", keys: [
                key("capsLock", 57, "caps lock", .r4, width: 1.75),
                key("a", 0, "A", .r2), key("s", 1, "S", .r2),
                key("d", 2, "D", .r2), key("f", 3, "F", .r2),
                key("g", 5, "G", .r2), key("h", 4, "H", .r2),
                key("j", 38, "J", .r2), key("k", 40, "K", .r2),
                key("l", 37, "L", .r2), key("semicolon", 41, ";", .r2),
                key("quote", 39, "'", .r2),
                key("enter", 36, "return", .r4, .enter, 2.25),
            ]),
            KeyboardLayoutRow(id: "zxcv", keys: [
                key("leftShift", 56, "shift", .r4, width: 2.25),
                key("z", 6, "Z", .r3), key("x", 7, "X", .r3),
                key("c", 8, "C", .r3), key("v", 9, "V", .r3),
                key("b", 11, "B", .r3), key("n", 45, "N", .r3),
                key("m", 46, "M", .r3), key("comma", 43, ",", .r3),
                key("period", 47, ".", .r3), key("slash", 44, "/", .r3),
                key("rightShift", 60, "shift", .r4, width: 2.75),
            ]),
            KeyboardLayoutRow(id: "bottom", keys: [
                key("function", 63, "fn", .r4, width: 1.25),
                key("leftControl", 59, "control", .r4, width: 1.25),
                key("leftOption", 58, "option", .r4, width: 1.25),
                key("leftCommand", 55, "command", .r4, width: 1.5),
                key("space", 49, "space", .r4, .space, 6.25),
                key("rightCommand", 54, "command", .r4, width: 1.5),
                key("rightOption", 61, "option", .r4, width: 1.25),
                key("rightControl", 62, "control", .r4, width: 1.25),
                key("leftArrow", 123, "←", .r4), key("downArrow", 125, "↓", .r4),
                key("upArrow", 126, "↑", .r4), key("rightArrow", 124, "→", .r4),
            ]),
        ]
    )

    private static let knownKeysByCode: [UInt16: KeyboardKeyDescriptor] = Dictionary(
        uniqueKeysWithValues: ansiTKL.keys.map { ($0.keyCode, $0) }
    )

    static func key(for keyCode: UInt16) -> KeyboardKeyDescriptor? {
        if let known = knownKeysByCode[keyCode] { return known }

        let special: KeyboardSpecialKeyID? = switch keyCode {
        case 49: .space
        case 36, 76: .enter
        case 51, 117: .backspace
        default: nil
        }
        return KeyboardKeyDescriptor(
            id: KeyboardKeyID("keycode.\(keyCode)"),
            keyCode: keyCode,
            label: "⌨︎\(keyCode)",
            row: .r4,
            specialKey: special
        )
    }

    static func keyID(for keyCode: UInt16) -> KeyboardKeyID? {
        key(for: keyCode)?.id
    }

    private static func key(
        _ id: String,
        _ keyCode: UInt16,
        _ label: String,
        _ row: KeyboardRowID,
        _ special: KeyboardSpecialKeyID? = nil,
        _ width: Double = 1,
        assignable: Bool = true
    ) -> KeyboardKeyDescriptor {
        KeyboardKeyDescriptor(
            id: KeyboardKeyID(id),
            keyCode: keyCode,
            label: label,
            row: row,
            specialKey: special,
            widthUnits: width,
            isAssignable: assignable
        )
    }

    private static func key(
        _ id: String,
        _ keyCode: UInt16,
        _ label: String,
        _ row: KeyboardRowID,
        _ special: KeyboardSpecialKeyID? = nil,
        width: Double,
        assignable: Bool = true
    ) -> KeyboardKeyDescriptor {
        key(id, keyCode, label, row, special, width, assignable: assignable)
    }
}
