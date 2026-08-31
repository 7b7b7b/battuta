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
        case .r0: "数字行".localized
        case .r1: "Q 行".localized
        case .r2: "A 行".localized
        case .r3: "Z 行".localized
        case .r4: "其他键".localized
        }
    }
}

enum KeyboardSpecialKeyID: String, CaseIterable, Codable, Hashable, Sendable {
    case space
    case enter
    case backspace

    var displayName: String {
        switch self {
        case .space: "空格".localized
        case .enter: "回车".localized
        case .backspace: "退格".localized
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

enum KeyboardVisualKeyContent: Hashable, Sendable {
    case key(KeyboardKeyID)
    case decoration(id: String, label: String, systemImage: String)

    var id: String {
        switch self {
        case let .key(keyID): "key.\(keyID.rawValue)"
        case let .decoration(id, _, _): "decoration.\(id)"
        }
    }

    var keyID: KeyboardKeyID? {
        guard case let .key(keyID) = self else { return nil }
        return keyID
    }

    var fallbackLabel: String {
        switch self {
        case let .key(keyID): keyID.rawValue
        case let .decoration(_, label, _): label
        }
    }

    var systemImage: String? {
        guard case let .decoration(_, _, systemImage) = self else { return nil }
        return systemImage
    }
}

enum KeyboardVisualVerticalSlot: Hashable, Sendable {
    case full
    case upperHalf
    case lowerHalf
}

struct KeyboardVisualPlacement: Identifiable, Hashable, Sendable {
    let content: KeyboardVisualKeyContent
    let row: Int
    let xUnits: Double
    let widthUnits: Double
    let verticalSlot: KeyboardVisualVerticalSlot

    var id: String { content.id }
}

struct KeyboardVisualLayout: Identifiable, Hashable, Sendable {
    let id: String
    let widthUnits: Double
    let rowCount: Int
    let placements: [KeyboardVisualPlacement]

    var keyIDs: Set<KeyboardKeyID> {
        Set(placements.compactMap(\.content.keyID))
    }

    func placements(inRow row: Int) -> [KeyboardVisualPlacement] {
        placements.filter { $0.row == row }
    }
}

/// Physical key geometry measured from Apple's front-facing 2024 compact Magic Keyboard image:
/// https://support.apple.com/121955
/// Every row spans 14.5 units; the upper and lower arrow keys share one physical column.
enum KeyboardVisualLayoutCatalog {
    static let magicKeyboardANSI = makeMagicKeyboardANSI()

    private enum Slot {
        case key(String, Double)
        case stacked(upper: String, lower: String, width: Double)
        case decoration(id: String, label: String, systemImage: String, width: Double)

        var widthUnits: Double {
            switch self {
            case let .key(_, width), let .stacked(_, _, width), let .decoration(_, _, _, width):
                width
            }
        }
    }

    private static func makeMagicKeyboardANSI() -> KeyboardVisualLayout {
        let rows: [[Slot]] = [
            [
                .key("escape", 1.5),
                .key("f1", 1), .key("f2", 1), .key("f3", 1), .key("f4", 1),
                .key("f5", 1), .key("f6", 1), .key("f7", 1), .key("f8", 1),
                .key("f9", 1), .key("f10", 1), .key("f11", 1), .key("f12", 1),
                .decoration(id: "lock", label: "锁定".localized, systemImage: "lock.fill", width: 1),
            ],
            [
                .key("backquote", 1),
                .key("digit1", 1), .key("digit2", 1), .key("digit3", 1),
                .key("digit4", 1), .key("digit5", 1), .key("digit6", 1),
                .key("digit7", 1), .key("digit8", 1), .key("digit9", 1),
                .key("digit0", 1), .key("minus", 1), .key("equal", 1),
                .key("backspace", 1.5),
            ],
            [
                .key("tab", 1.5),
                .key("q", 1), .key("w", 1), .key("e", 1), .key("r", 1),
                .key("t", 1), .key("y", 1), .key("u", 1), .key("i", 1),
                .key("o", 1), .key("p", 1), .key("leftBracket", 1),
                .key("rightBracket", 1), .key("backslash", 1),
            ],
            [
                .key("capsLock", 1.75),
                .key("a", 1), .key("s", 1), .key("d", 1), .key("f", 1),
                .key("g", 1), .key("h", 1), .key("j", 1), .key("k", 1),
                .key("l", 1), .key("semicolon", 1), .key("quote", 1),
                .key("enter", 1.75),
            ],
            [
                .key("leftShift", 2.25),
                .key("z", 1), .key("x", 1), .key("c", 1), .key("v", 1),
                .key("b", 1), .key("n", 1), .key("m", 1), .key("comma", 1),
                .key("period", 1), .key("slash", 1),
                .key("rightShift", 2.25),
            ],
            [
                .key("function", 1), .key("leftControl", 1), .key("leftOption", 1),
                .key("leftCommand", 1.25), .key("space", 5),
                .key("rightCommand", 1.25), .key("rightOption", 1),
                .key("leftArrow", 1),
                .stacked(upper: "upArrow", lower: "downArrow", width: 1),
                .key("rightArrow", 1),
            ],
        ]

        var placements = [KeyboardVisualPlacement]()
        for (rowIndex, slots) in rows.enumerated() {
            var xUnits = 0.0
            for slot in slots {
                switch slot {
                case let .key(id, width):
                    placements.append(KeyboardVisualPlacement(
                        content: .key(KeyboardKeyID(id)),
                        row: rowIndex,
                        xUnits: xUnits,
                        widthUnits: width,
                        verticalSlot: .full
                    ))
                case let .stacked(upper, lower, width):
                    placements.append(KeyboardVisualPlacement(
                        content: .key(KeyboardKeyID(upper)),
                        row: rowIndex,
                        xUnits: xUnits,
                        widthUnits: width,
                        verticalSlot: .upperHalf
                    ))
                    placements.append(KeyboardVisualPlacement(
                        content: .key(KeyboardKeyID(lower)),
                        row: rowIndex,
                        xUnits: xUnits,
                        widthUnits: width,
                        verticalSlot: .lowerHalf
                    ))
                case let .decoration(id, label, systemImage, width):
                    placements.append(KeyboardVisualPlacement(
                        content: .decoration(id: id, label: label, systemImage: systemImage),
                        row: rowIndex,
                        xUnits: xUnits,
                        widthUnits: width,
                        verticalSlot: .full
                    ))
                }
                xUnits += slot.widthUnits
            }
            precondition(abs(xUnits - 14.5) < 0.000_1, "Magic Keyboard row must span 14.5U")
        }

        return KeyboardVisualLayout(
            id: "apple-magic-keyboard-us-ansi-2024",
            widthUnits: 14.5,
            rowCount: rows.count,
            placements: placements
        )
    }
}

/// Common keys found on Apple's extended keyboards and third-party Mac layouts.
/// Keeping them in the shared catalog lets DIY mapping and statistics use the
/// same key identities and labels.
enum KeyboardExtendedLayoutCatalog {
    static let rows: [KeyboardLayoutRow] = [
        row("navigation", [
            key("help", 114, "help"), key("home", 115, "home"),
            key("pageUp", 116, "pg up"),
            key("forwardDelete", 117, "⌦", special: .backspace),
            key("end", 119, "end"), key("pageDown", 121, "pg dn"),
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
            key("keypad3", 85, "3"),
            key("keypadEnter", 76, "enter", special: .enter, width: 1.5),
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
            key("volumeUp", 72, "音量+".localized, width: 1.5),
            key("volumeDown", 73, "音量−".localized, width: 1.5),
            key("mute", 74, "静音".localized, width: 1.5),
        ]),
    ]

    static var keys: [KeyboardKeyDescriptor] {
        rows.flatMap(\.keys)
    }

    private static func row(
        _ id: String,
        _ keys: [KeyboardKeyDescriptor]
    ) -> KeyboardLayoutRow {
        KeyboardLayoutRow(id: "extended.\(id)", keys: keys)
    }

    private static func key(
        _ id: String,
        _ keyCode: UInt16,
        _ label: String,
        special: KeyboardSpecialKeyID? = nil,
        width: Double = 1
    ) -> KeyboardKeyDescriptor {
        KeyboardKeyDescriptor(
            id: KeyboardKeyID("extended.\(id)"),
            keyCode: keyCode,
            label: label,
            row: .r4,
            specialKey: special,
            widthUnits: width
        )
    }
}

enum KeyboardLayoutCatalog {
    static let defaultLayoutID = "mac-ansi-tkl-v1"

    static let ansiTKL = KeyboardLayout(
        id: defaultLayoutID,
        displayName: "Mac US ANSI 紧凑型".localized,
        rows: [
            KeyboardLayoutRow(id: "function", keys: [
                key("escape", 53, "esc", .r4, width: 1.5),
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
                key("backspace", 51, "delete", .r4, .backspace, 1.5),
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
                key("backslash", 42, "\\", .r1),
            ]),
            KeyboardLayoutRow(id: "home", keys: [
                key("capsLock", 57, "caps lock", .r4, width: 1.75),
                key("a", 0, "A", .r2), key("s", 1, "S", .r2),
                key("d", 2, "D", .r2), key("f", 3, "F", .r2),
                key("g", 5, "G", .r2), key("h", 4, "H", .r2),
                key("j", 38, "J", .r2), key("k", 40, "K", .r2),
                key("l", 37, "L", .r2), key("semicolon", 41, ";", .r2),
                key("quote", 39, "'", .r2),
                key("enter", 36, "return", .r4, .enter, 1.75),
            ]),
            KeyboardLayoutRow(id: "zxcv", keys: [
                key("leftShift", 56, "shift", .r4, width: 2.25),
                key("z", 6, "Z", .r3), key("x", 7, "X", .r3),
                key("c", 8, "C", .r3), key("v", 9, "V", .r3),
                key("b", 11, "B", .r3), key("n", 45, "N", .r3),
                key("m", 46, "M", .r3), key("comma", 43, ",", .r3),
                key("period", 47, ".", .r3), key("slash", 44, "/", .r3),
                key("rightShift", 60, "shift", .r4, width: 2.25),
            ]),
            KeyboardLayoutRow(id: "bottom", keys: [
                key("function", 63, "fn", .r4),
                key("leftControl", 59, "control", .r4),
                key("leftOption", 58, "option", .r4),
                key("leftCommand", 55, "command", .r4, width: 1.25),
                key("space", 49, "space", .r4, .space, 5),
                key("rightCommand", 54, "command", .r4, width: 1.25),
                key("rightOption", 61, "option", .r4),
                key("rightControl", 62, "control", .r4),
                key("leftArrow", 123, "←", .r4), key("upArrow", 126, "↑", .r4),
                key("downArrow", 125, "↓", .r4), key("rightArrow", 124, "→", .r4),
            ]),
        ]
    )

    private static let knownKeysByCode: [UInt16: KeyboardKeyDescriptor] = Dictionary(
        uniqueKeysWithValues: (ansiTKL.keys + KeyboardExtendedLayoutCatalog.keys)
            .map { ($0.keyCode, $0) }
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
