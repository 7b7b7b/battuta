import Foundation

enum AppLanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    var id: Self { self }

    var localizationIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }

    var displayNameKey: String {
        switch self {
        case .system: "跟随系统"
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }
}

enum L10n {
    private struct State {
        let languagePreference: AppLanguagePreference
        let resolvedLocalization: String
        let bundle: Bundle
        let locale: Locale
    }

    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var state: State

        init(state: State) {
            self.state = state
        }

        func replace(with state: State) {
            lock.lock()
            self.state = state
            lock.unlock()
        }

        func current() -> State {
            lock.lock()
            defer { lock.unlock() }
            return state
        }
    }

    private static let supportedLocalizations = ["zh-Hans", "en"]
    private static let fallbackLocalization = "en"
    private static let storage = Storage(state: makeState(for: .system))

    static func configure(for preference: AppLanguagePreference) {
        storage.replace(with: makeState(for: preference))
    }

    static func refreshSystemLocalizationIfNeeded() -> Bool {
        let previous = currentState()
        guard previous.languagePreference == .system else { return false }
        let refreshed = makeState(for: .system)
        guard refreshed.resolvedLocalization != previous.resolvedLocalization else {
            return false
        }
        storage.replace(with: refreshed)
        return true
    }

    static func tr(_ key: String) -> String {
        let snapshot = currentState()
        return snapshot.bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ format: String, _ arguments: CVarArg...) -> String {
        let snapshot = currentState()
        return String(
            format: snapshot.bundle.localizedString(forKey: format, value: format, table: nil),
            locale: snapshot.locale,
            arguments: arguments
        )
    }

    static func locale(for preference: AppLanguagePreference) -> Locale {
        makeState(for: preference).locale
    }

    static var locale: Locale {
        currentState().locale
    }

    private static func currentState() -> State {
        storage.current()
    }

    private static func makeState(for preference: AppLanguagePreference) -> State {
        let resolvedLocalization = resolvedLocalizationIdentifier(for: preference)
        return State(
            languagePreference: preference,
            resolvedLocalization: resolvedLocalization,
            bundle: localizedBundle(for: resolvedLocalization),
            locale: preference == .system ? .autoupdatingCurrent : locale(for: resolvedLocalization)
        )
    }

    private static func resolvedLocalizationIdentifier(
        for preference: AppLanguagePreference
    ) -> String {
        if let localization = preference.localizationIdentifier {
            return localization
        }

        let preferences = UserDefaults.standard.stringArray(forKey: "AppleLanguages")
            ?? Locale.preferredLanguages
        let preferred = Bundle.preferredLocalizations(
            from: supportedLocalizations,
            forPreferences: preferences
        ).first
        return canonicalLocalizationIdentifier(preferred)
    }

    private static func canonicalLocalizationIdentifier(_ identifier: String?) -> String {
        guard let identifier else { return fallbackLocalization }
        let lowercased = identifier.lowercased()
        if lowercased.hasPrefix("zh") {
            return "zh-Hans"
        }
        if lowercased.hasPrefix("en") {
            return "en"
        }
        return fallbackLocalization
    }

    private static func localizedBundle(for localization: String) -> Bundle {
        guard let path = Bundle.main.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    private static func locale(for localization: String) -> Locale {
        switch localization {
        case "zh-Hans":
            return Locale(identifier: "zh-Hans")
        default:
            return Locale(identifier: "en")
        }
    }
}

extension String {
    var localized: String {
        L10n.tr(self)
    }
}
