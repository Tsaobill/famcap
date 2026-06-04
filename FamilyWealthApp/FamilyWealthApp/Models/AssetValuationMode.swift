import Foundation

enum AssetValuationMode: String, CaseIterable, Codable, Identifiable {
    case standard
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return AppLocalizer.string("asset.valuation.standard")
        case .custom:
            return AppLocalizer.string("asset.valuation.custom")
        }
    }
}
