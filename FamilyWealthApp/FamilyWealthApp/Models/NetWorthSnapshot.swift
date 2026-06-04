import Foundation
import SwiftData

@Model
final class NetWorthSnapshot {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var baseCurrencyCode: String
    var totalValue: Double
    var capturedAt: Date

    init(
        id: UUID = UUID(),
        householdID: UUID,
        baseCurrencyCode: String,
        totalValue: Double,
        capturedAt: Date = .now
    ) {
        self.id = id
        self.householdID = householdID
        self.baseCurrencyCode = baseCurrencyCode
        self.totalValue = totalValue
        self.capturedAt = capturedAt
    }
}
