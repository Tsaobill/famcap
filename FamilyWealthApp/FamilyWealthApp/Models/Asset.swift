import Foundation
import SwiftData

@Model
final class Asset {
    @Attribute(.unique) var id: UUID
    var name: String
    var typeRawValue: String
    var valuationModeRawValue: String = "custom"
    var symbol: String = ""
    var marketRawValue: String = StockMarket.global.rawValue
    var quantity: Double = 0
    var autoSyncPrice: Bool = false
    var latestUnitPrice: Double = 0
    var lastQuoteAt: Date?
    var categoryTag: String = ""
    var accountPlatformTag: String = ""
    var currencyCode: String
    var marketValue: Double
    var note: String
    var createdAt: Date
    var updatedAt: Date

    var owner: Member?
    var household: Household?

    init(
        id: UUID = UUID(),
        name: String,
        type: AssetType,
        valuationMode: AssetValuationMode = .custom,
        symbol: String = "",
        market: StockMarket = .global,
        quantity: Double = 0,
        autoSyncPrice: Bool = false,
        latestUnitPrice: Double = 0,
        lastQuoteAt: Date? = nil,
        categoryTag: String = "",
        accountPlatformTag: String = "",
        currencyCode: String,
        marketValue: Double,
        note: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        owner: Member? = nil,
        household: Household? = nil
    ) {
        self.id = id
        self.name = name
        typeRawValue = type.rawValue
        valuationModeRawValue = valuationMode.rawValue
        self.symbol = symbol
        marketRawValue = market.rawValue
        self.quantity = quantity
        self.autoSyncPrice = autoSyncPrice
        self.latestUnitPrice = latestUnitPrice
        self.lastQuoteAt = lastQuoteAt
        self.categoryTag = categoryTag
        self.accountPlatformTag = accountPlatformTag
        self.currencyCode = currencyCode
        self.marketValue = marketValue
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.owner = owner
        self.household = household
    }

    var type: AssetType {
        get {
            AssetType(rawValue: typeRawValue) ?? .other
        }
        set {
            typeRawValue = newValue.rawValue
        }
    }

    var valuationMode: AssetValuationMode {
        get {
            AssetValuationMode(rawValue: valuationModeRawValue) ?? .custom
        }
        set {
            valuationModeRawValue = newValue.rawValue
        }
    }

    var market: StockMarket {
        get {
            StockMarket(rawValue: marketRawValue) ?? .global
        }
        set {
            marketRawValue = newValue.rawValue
        }
    }

    var isTrackableQuoteAsset: Bool {
        let trackableType = type == .stock || type == .crypto
        return trackableType
            && valuationMode == .standard
            && autoSyncPrice
            && quantity > 0
            && !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
