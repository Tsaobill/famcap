import Foundation

enum AssetType: String, CaseIterable, Codable, Identifiable {
    case cash
    case bankDeposit
    case balance
    case stock
    case fund
    case wealthManagement
    case bond
    case crypto
    case realEstate
    case insurance
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash:
            return AppLocalizer.string("asset.type.cash")
        case .bankDeposit:
            return AppLocalizer.string("asset.type.bankDeposit")
        case .balance:
            return AppLocalizer.string("asset.type.balance")
        case .stock:
            return AppLocalizer.string("asset.type.stock")
        case .fund:
            return AppLocalizer.string("asset.type.fund")
        case .wealthManagement:
            return AppLocalizer.string("asset.type.wealthManagement")
        case .bond:
            return AppLocalizer.string("asset.type.bond")
        case .crypto:
            return AppLocalizer.string("asset.type.crypto")
        case .realEstate:
            return AppLocalizer.string("asset.type.realEstate")
        case .insurance:
            return AppLocalizer.string("asset.type.insurance")
        case .other:
            return AppLocalizer.string("asset.type.other")
        }
    }
}
