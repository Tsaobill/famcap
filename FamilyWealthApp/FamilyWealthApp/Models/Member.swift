import Foundation
import SwiftData

@Model
final class Member {
    @Attribute(.unique) var id: UUID
    var name: String
    var relation: String
    var isPrimary: Bool
    var createdAt: Date

    var household: Household?

    @Relationship(deleteRule: .nullify, inverse: \Asset.owner)
    var assets: [Asset]

    init(
        id: UUID = UUID(),
        name: String,
        relation: String,
        isPrimary: Bool = false,
        createdAt: Date = .now,
        household: Household? = nil
    ) {
        self.id = id
        self.name = name
        self.relation = relation
        self.isPrimary = isPrimary
        self.createdAt = createdAt
        self.household = household
        assets = []
    }

    var totalValue: Double {
        assets.reduce(0) { $0 + $1.marketValue }
    }
}
