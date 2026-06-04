import Foundation

enum StockMarket: String, CaseIterable, Codable, Identifiable {
    case us
    case hk
    case global

    var id: String { rawValue }

    var title: String {
        switch self {
        case .us:
            return AppLocalizer.string("stock.market.us")
        case .hk:
            return AppLocalizer.string("stock.market.hk")
        case .global:
            return AppLocalizer.string("stock.market.global")
        }
    }
}
