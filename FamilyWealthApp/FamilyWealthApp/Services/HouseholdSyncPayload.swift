import Foundation
import SwiftData

struct HouseholdSyncEnvelope: Codable {
    let senderName: String
    let exportedAt: Date
    let household: HouseholdSyncPayload
    let members: [MemberSyncPayload]
    let assets: [AssetSyncPayload]
}

struct HouseholdSyncPayload: Codable {
    let id: UUID
    let name: String
    let createdAt: Date
}

struct MemberSyncPayload: Codable {
    let id: UUID
    let name: String
    let relation: String
    let isPrimary: Bool
    let createdAt: Date
}

struct AssetSyncPayload: Codable {
    let id: UUID
    let name: String
    let typeRawValue: String
    let valuationModeRawValue: String
    let symbol: String
    let marketRawValue: String
    let quantity: Double
    let autoSyncPrice: Bool
    let latestUnitPrice: Double
    let lastQuoteAt: Date?
    let categoryTag: String
    let accountPlatformTag: String
    let currencyCode: String
    let marketValue: Double
    let note: String
    let createdAt: Date
    let updatedAt: Date
    let ownerID: UUID?
}

struct HouseholdSyncImportSummary {
    let householdInserted: Bool
    let membersInserted: Int
    let membersUpdated: Int
    let assetsInserted: Int
    let assetsUpdated: Int
}

enum HouseholdSyncCodec {
    static func makeEnvelope(
        from household: Household,
        senderName: String
    ) -> HouseholdSyncEnvelope {
        let members = household.members.map {
            MemberSyncPayload(
                id: $0.id,
                name: $0.name,
                relation: $0.relation,
                isPrimary: $0.isPrimary,
                createdAt: $0.createdAt
            )
        }

        let assets = household.assets.map {
            AssetSyncPayload(
                id: $0.id,
                name: $0.name,
                typeRawValue: $0.typeRawValue,
                valuationModeRawValue: $0.valuationModeRawValue,
                symbol: $0.symbol,
                marketRawValue: $0.marketRawValue,
                quantity: $0.quantity,
                autoSyncPrice: $0.autoSyncPrice,
                latestUnitPrice: $0.latestUnitPrice,
                lastQuoteAt: $0.lastQuoteAt,
                categoryTag: $0.categoryTag,
                accountPlatformTag: $0.accountPlatformTag,
                currencyCode: $0.currencyCode,
                marketValue: $0.marketValue,
                note: $0.note,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                ownerID: $0.owner?.id
            )
        }

        return HouseholdSyncEnvelope(
            senderName: senderName,
            exportedAt: .now,
            household: HouseholdSyncPayload(
                id: household.id,
                name: household.name,
                createdAt: household.createdAt
            ),
            members: members,
            assets: assets
        )
    }

    static func importEnvelope(
        _ envelope: HouseholdSyncEnvelope,
        into modelContext: ModelContext
    ) throws -> HouseholdSyncImportSummary {
        let existingHouseholds = try modelContext.fetch(FetchDescriptor<Household>())
        let existingMembers = try modelContext.fetch(FetchDescriptor<Member>())
        let existingAssets = try modelContext.fetch(FetchDescriptor<Asset>())

        let householdPayload = envelope.household
        let household: Household
        var insertedHousehold = false

        if let matched = existingHouseholds.first(where: { $0.id == householdPayload.id }) {
            household = matched
            household.name = householdPayload.name
            household.createdAt = householdPayload.createdAt
        } else {
            household = Household(
                id: householdPayload.id,
                name: householdPayload.name,
                createdAt: householdPayload.createdAt
            )
            modelContext.insert(household)
            insertedHousehold = true
        }

        var membersByID = Dictionary(uniqueKeysWithValues: existingMembers.map { ($0.id, $0) })
        var assetsByID = Dictionary(uniqueKeysWithValues: existingAssets.map { ($0.id, $0) })

        var membersInserted = 0
        var membersUpdated = 0
        var assetsInserted = 0
        var assetsUpdated = 0

        for payload in envelope.members {
            if let member = membersByID[payload.id] {
                member.name = payload.name
                member.relation = payload.relation
                member.isPrimary = payload.isPrimary
                member.createdAt = payload.createdAt
                member.household = household
                membersUpdated += 1
            } else {
                let member = Member(
                    id: payload.id,
                    name: payload.name,
                    relation: payload.relation,
                    isPrimary: payload.isPrimary,
                    createdAt: payload.createdAt,
                    household: household
                )
                modelContext.insert(member)
                membersByID[member.id] = member
                membersInserted += 1
            }
        }

        for payload in envelope.assets {
            let owner = payload.ownerID.flatMap { membersByID[$0] }
            let type = AssetType(rawValue: payload.typeRawValue) ?? .other
            let valuationMode = AssetValuationMode(rawValue: payload.valuationModeRawValue) ?? .custom
            let market = StockMarket(rawValue: payload.marketRawValue) ?? .global

            if let asset = assetsByID[payload.id] {
                asset.name = payload.name
                asset.type = type
                asset.valuationMode = valuationMode
                asset.symbol = payload.symbol
                asset.market = market
                asset.quantity = payload.quantity
                asset.autoSyncPrice = payload.autoSyncPrice
                asset.latestUnitPrice = payload.latestUnitPrice
                asset.lastQuoteAt = payload.lastQuoteAt
                asset.categoryTag = payload.categoryTag
                asset.accountPlatformTag = payload.accountPlatformTag
                asset.currencyCode = payload.currencyCode
                asset.marketValue = payload.marketValue
                asset.note = payload.note
                asset.createdAt = payload.createdAt
                asset.updatedAt = payload.updatedAt
                asset.owner = owner
                asset.household = household
                assetsUpdated += 1
            } else {
                let asset = Asset(
                    id: payload.id,
                    name: payload.name,
                    type: type,
                    valuationMode: valuationMode,
                    symbol: payload.symbol,
                    market: market,
                    quantity: payload.quantity,
                    autoSyncPrice: payload.autoSyncPrice,
                    latestUnitPrice: payload.latestUnitPrice,
                    lastQuoteAt: payload.lastQuoteAt,
                    categoryTag: payload.categoryTag,
                    accountPlatformTag: payload.accountPlatformTag,
                    currencyCode: payload.currencyCode,
                    marketValue: payload.marketValue,
                    note: payload.note,
                    createdAt: payload.createdAt,
                    updatedAt: payload.updatedAt,
                    owner: owner,
                    household: household
                )
                modelContext.insert(asset)
                assetsByID[asset.id] = asset
                assetsInserted += 1
            }
        }

        try modelContext.save()

        return HouseholdSyncImportSummary(
            householdInserted: insertedHousehold,
            membersInserted: membersInserted,
            membersUpdated: membersUpdated,
            assetsInserted: assetsInserted,
            assetsUpdated: assetsUpdated
        )
    }
}
