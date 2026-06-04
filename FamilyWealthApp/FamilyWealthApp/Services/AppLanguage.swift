import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .zhHans:
            return Locale(identifier: "zh-Hans")
        case .en:
            return Locale(identifier: "en")
        }
    }

    var title: String {
        switch self {
        case .system:
            return AppLocalizer.string("language.option.system")
        case .zhHans:
            return AppLocalizer.string("language.option.zhHans")
        case .en:
            return AppLocalizer.string("language.option.en")
        }
    }
}
