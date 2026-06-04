import Foundation
import SwiftData

@Model
final class Household {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Member.household)
    var members: [Member]

    @Relationship(deleteRule: .cascade, inverse: \Asset.household)
    var assets: [Asset]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        members = []
        assets = []
    }

    var totalValue: Double {
        assets.reduce(0) { $0 + $1.marketValue }
    }
}
