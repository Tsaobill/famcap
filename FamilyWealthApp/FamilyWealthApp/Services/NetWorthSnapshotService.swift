import Foundation
import SwiftData

enum NetWorthSnapshotService {
    static func recordSnapshotIfNeeded(
        householdID: UUID,
        baseCurrencyCode: String,
        totalValue: Double,
        modelContext: ModelContext,
        minimumInterval: TimeInterval = 6 * 60 * 60
    ) {
        var descriptor = FetchDescriptor<NetWorthSnapshot>(
            predicate: #Predicate<NetWorthSnapshot> {
                $0.householdID == householdID && $0.baseCurrencyCode == baseCurrencyCode
            },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        let latest = (try? modelContext.fetch(descriptor))?.first
        let now = Date.now

        if let latest {
            let elapsed = now.timeIntervalSince(latest.capturedAt)
            let baseline = max(abs(latest.totalValue), 1)
            let diffRatio = abs(totalValue - latest.totalValue) / baseline
            if elapsed < minimumInterval && diffRatio < 0.005 {
                return
            }
        }

        let snapshot = NetWorthSnapshot(
            householdID: householdID,
            baseCurrencyCode: baseCurrencyCode,
            totalValue: totalValue,
            capturedAt: now
        )
        modelContext.insert(snapshot)
        try? modelContext.save()
    }
}
