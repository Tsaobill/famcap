import Foundation
import SwiftData

enum AppSeeder {
    static func seedIfNeeded(modelContext: ModelContext) {
        var descriptor = FetchDescriptor<Household>()
        descriptor.fetchLimit = 1

        let households = (try? modelContext.fetch(descriptor)) ?? []
        guard households.isEmpty else {
            return
        }

        let household = Household(name: "Our Household")

        let you = Member(
            name: "You",
            relation: "Self",
            isPrimary: true,
            household: household
        )

        let partner = Member(
            name: "Partner",
            relation: "Spouse",
            household: household
        )

        let checking = Asset(
            name: "Checking Account",
            type: .bankDeposit,
            currencyCode: "USD",
            marketValue: 20_000,
            note: "Sample data",
            owner: you,
            household: household
        )

        let usStock = Asset(
            name: "Apple",
            type: .stock,
            valuationMode: .standard,
            symbol: "AAPL",
            market: .us,
            quantity: 10,
            autoSyncPrice: true,
            currencyCode: "USD",
            marketValue: 1_800,
            note: "Auto quote demo",
            owner: you,
            household: household
        )

        let hkStock = Asset(
            name: "Tencent",
            type: .stock,
            valuationMode: .standard,
            symbol: "0700",
            market: .hk,
            quantity: 50,
            autoSyncPrice: true,
            currencyCode: "HKD",
            marketValue: 15_000,
            note: "HK quote demo",
            owner: partner,
            household: household
        )

        modelContext.insert(household)
        modelContext.insert(you)
        modelContext.insert(partner)
        modelContext.insert(checking)
        modelContext.insert(usStock)
        modelContext.insert(hkStock)

        let snapshot1 = NetWorthSnapshot(
            householdID: household.id,
            baseCurrencyCode: "USD",
            totalValue: 30_000,
            capturedAt: Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        )
        let snapshot2 = NetWorthSnapshot(
            householdID: household.id,
            baseCurrencyCode: "USD",
            totalValue: 36_800,
            capturedAt: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        )
        modelContext.insert(snapshot1)
        modelContext.insert(snapshot2)

        try? modelContext.save()
    }
}
