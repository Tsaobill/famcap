import Foundation

enum AppLocalizer {
    private static let appLanguageCodeStorageKey = "appLanguageCode"

    static func string(_ key: String) -> String {
        NSLocalizedString(
            key,
            tableName: nil,
            bundle: activeBundle(),
            value: key,
            comment: ""
        )
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: activeLocale(),
            arguments: arguments
        )
    }

    private static func activeBundle() -> Bundle {
        guard let rawValue = UserDefaults.standard.string(forKey: appLanguageCodeStorageKey),
              let language = AppLanguage(rawValue: rawValue),
              language != .system
        else {
            return .main
        }

        if let bundle = bundle(for: language.rawValue) {
            return bundle
        }

        if let baseLanguage = language.rawValue.split(separator: "-").first,
           let bundle = bundle(for: String(baseLanguage))
        {
            return bundle
        }

        return .main
    }

    private static func bundle(for languageCode: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    private static func activeLocale() -> Locale {
        guard let rawValue = UserDefaults.standard.string(forKey: appLanguageCodeStorageKey),
              let language = AppLanguage(rawValue: rawValue)
        else {
            return .autoupdatingCurrent
        }

        return language.locale
    }
}
