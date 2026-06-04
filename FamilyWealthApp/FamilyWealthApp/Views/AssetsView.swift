import SwiftData
import SwiftUI

private enum OwnerFilter: Equatable {
    case all
    case unassigned
    case member(UUID)
}

private enum AssetSortMode: String, CaseIterable, Identifiable {
    case valueDesc
    case valueAsc
    case updatedDesc
    case nameAsc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .valueDesc:
            return AppLocalizer.string("assets.sort.valueDesc")
        case .valueAsc:
            return AppLocalizer.string("assets.sort.valueAsc")
        case .updatedDesc:
            return AppLocalizer.string("assets.sort.updatedDesc")
        case .nameAsc:
            return AppLocalizer.string("assets.sort.nameAsc")
        }
    }
}

private enum AssetEditorMode {
    case create
    case edit
}

private let floatingActionButtonSize: CGFloat = 56
private let floatingActionButtonBottomInset: CGFloat = floatingActionButtonSize / 2

struct AssetsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Asset.updatedAt, order: .reverse) private var assets: [Asset]
    @Query(sort: \Member.createdAt) private var members: [Member]
    @Query(sort: \Household.createdAt) private var households: [Household]

    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = "USD"

    @StateObject private var marketDataCoordinator = MarketDataCoordinator()

    @State private var showAddAsset = false
    @State private var showAddMember = false
    @State private var searchText = ""
    @State private var typeFilter: AssetType?
    @State private var ownerFilter: OwnerFilter = .all
    @State private var sortMode: AssetSortMode = .valueDesc

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                memberSummarySection
                filterBar

                List {
                    Section(AppLocalizer.string("assets.list.section")) {
                        if filteredSortedAssets.isEmpty {
                            Text(AppLocalizer.string("assets.list.empty"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredSortedAssets, id: \.id) { asset in
                                NavigationLink {
                                    AssetDetailView(
                                        marketDataCoordinator: marketDataCoordinator,
                                        asset: asset
                                    )
                                } label: {
                                    assetRow(asset)
                                }
                            }
                            .onDelete(perform: deleteAssets)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: AppLocalizer.string("assets.search.prompt"))
            }
            .navigationTitle(AppLocalizer.string("tab.assets"))
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showAddAsset = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: floatingActionButtonSize, height: floatingActionButtonSize)
                        .background(Color.accentColor, in: Circle())
                        .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, floatingActionButtonBottomInset)
            }
        }
        .task(id: "\(normalizedBaseCurrency)-\(assets.count)-\(assets.map { $0.currencyCode }.joined(separator: ","))") {
            await marketDataCoordinator.refreshRatesOnly(
                assets: assets,
                baseCurrency: normalizedBaseCurrency
            )
        }
        .sheet(isPresented: $showAddAsset) {
            if let household = ensureHousehold() {
                AssetEditorView(
                    mode: .create,
                    household: household,
                    members: members,
                    asset: nil
                )
            }
        }
        .sheet(isPresented: $showAddMember) {
            if let household = ensureHousehold() {
                AssetListAddMemberView(household: household)
            }
        }
    }

    private var normalizedBaseCurrency: String {
        baseCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var householdTotalBase: Double {
        convertedTotal(for: assets)
    }

    private var sortedMembers: [Member] {
        members.sorted { left, right in
            let leftTotal = convertedTotal(for: left.assets)
            let rightTotal = convertedTotal(for: right.assets)
            if leftTotal == rightTotal {
                return left.createdAt < right.createdAt
            }
            return leftTotal > rightTotal
        }
    }

    private var memberTotalsBase: [UUID: Double] {
        Dictionary(uniqueKeysWithValues: members.map { member in
            (member.id, convertedTotal(for: member.assets))
        })
    }

    private var ownerFilterTitle: String {
        switch ownerFilter {
        case .all:
            return AppLocalizer.string("common.all")
        case .unassigned:
            return AppLocalizer.string("common.unassigned")
        case .member(let memberID):
            return members.first(where: { $0.id == memberID })?.name ?? AppLocalizer.string("common.member")
        }
    }

    private var filteredSortedAssets: [Asset] {
        let filtered = assets.filter { asset in
            matchesTypeFilter(asset)
                && matchesOwnerFilter(asset)
                && matchesSearch(asset)
        }

        return filtered.sorted { left, right in
            switch sortMode {
            case .valueDesc:
                let leftBase = marketDataCoordinator.convertedToBase(amount: left.marketValue, from: left.currencyCode)
                let rightBase = marketDataCoordinator.convertedToBase(amount: right.marketValue, from: right.currencyCode)
                if leftBase == rightBase {
                    return left.updatedAt > right.updatedAt
                }
                return leftBase > rightBase
            case .valueAsc:
                let leftBase = marketDataCoordinator.convertedToBase(amount: left.marketValue, from: left.currencyCode)
                let rightBase = marketDataCoordinator.convertedToBase(amount: right.marketValue, from: right.currencyCode)
                if leftBase == rightBase {
                    return left.updatedAt > right.updatedAt
                }
                return leftBase < rightBase
            case .updatedDesc:
                return left.updatedAt > right.updatedAt
            case .nameAsc:
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
        }
    }

    @ViewBuilder
    private var memberSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(AppLocalizer.string("assets.member.summary"))
                    .font(.headline)
                Spacer()
                Button(AppLocalizer.string("member.add")) {
                    showAddMember = true
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if sortedMembers.isEmpty {
                Text(AppLocalizer.string("assets.member.empty"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(sortedMembers, id: \.id) { member in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(member.name)
                                        .font(.subheadline.weight(.semibold))
                                    if member.isPrimary {
                                        Text(AppLocalizer.string("member.primary"))
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.2), in: Capsule())
                                    }
                                }

                                Text(displayMemberRelation(member.relation))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(
                                    CurrencyFormatter.string(
                                        value: convertedTotal(for: member.assets),
                                        currencyCode: normalizedBaseCurrency
                                    )
                                )
                                .font(.subheadline.monospacedDigit())

                                Text(AppLocalizer.string("assets.member.assetCount", member.assets.count))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(width: 180, alignment: .leading)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Menu {
                    Button(AppLocalizer.string("assets.filter.type.allTypes")) { typeFilter = nil }
                    ForEach(AssetType.allCases) { type in
                        Button(type.title) { typeFilter = type }
                    }
                } label: {
                    filterChip(
                        AppLocalizer.string(
                            "assets.filter.type.chip",
                            typeFilter?.title ?? AppLocalizer.string("common.all")
                        )
                    )
                }

                Menu {
                    Button(AppLocalizer.string("common.all")) {
                        ownerFilter = .all
                    }
                    Button(AppLocalizer.string("common.unassigned")) {
                        ownerFilter = .unassigned
                    }
                    if !members.isEmpty {
                        Divider()
                        ForEach(members, id: \.id) { member in
                            Button(member.name) {
                                ownerFilter = .member(member.id)
                            }
                        }
                    }
                } label: {
                    filterChip(AppLocalizer.string("assets.filter.owner.chip", ownerFilterTitle))
                }

                Menu {
                    ForEach(AssetSortMode.allCases) { mode in
                        Button(mode.title) { sortMode = mode }
                    }
                } label: {
                    filterChip(AppLocalizer.string("assets.filter.sort.chip", sortMode.title))
                }

                if typeFilter != nil || ownerFilter != .all {
                    Button(AppLocalizer.string("assets.filter.clear")) {
                        typeFilter = nil
                        ownerFilter = .all
                    }
                    .font(.subheadline)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func assetRow(_ asset: Asset) -> some View {
        let baseValue = marketDataCoordinator.convertedToBase(
            amount: asset.marketValue,
            from: asset.currencyCode
        )
        let householdPercent = householdTotalBase > 0 ? baseValue / householdTotalBase : 0
        let memberTotal = asset.owner.flatMap { memberTotalsBase[$0.id] } ?? 0
        let memberPercent = memberTotal > 0 ? baseValue / memberTotal : 0

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(asset.name)
                    .font(.headline)
                Text(asset.type.title)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2), in: Capsule())
                Text(asset.valuationMode.title)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                Spacer()
            }

            HStack(alignment: .firstTextBaseline) {
                Text(asset.owner?.name ?? AppLocalizer.string("common.unassigned"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CurrencyFormatter.string(value: asset.marketValue, currencyCode: asset.currencyCode))
                        .font(.subheadline.monospacedDigit())
                    if asset.currencyCode != normalizedBaseCurrency {
                        Text(CurrencyFormatter.string(value: baseValue, currencyCode: normalizedBaseCurrency))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                if !asset.symbol.isEmpty {
                    Text(asset.symbol)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                }

                if asset.quantity > 0 {
                    Text(
                        AppLocalizer.string(
                            "assets.quantity.value",
                            asset.quantity.formatted(.number.precision(.fractionLength(0 ... 4)))
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !asset.categoryTag.isEmpty {
                    Text(asset.categoryTag)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.18), in: Capsule())
                }

                if !asset.accountPlatformTag.isEmpty {
                    Text(asset.accountPlatformTag)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.18), in: Capsule())
                }
            }

            Text(
                asset.owner == nil
                    ? AppLocalizer.string(
                        "assets.share.unassigned",
                        householdPercent.formatted(.percent.precision(.fractionLength(1)))
                    )
                    : AppLocalizer.string(
                        "assets.share.assigned",
                        householdPercent.formatted(.percent.precision(.fractionLength(1))),
                        memberPercent.formatted(.percent.precision(.fractionLength(1)))
                    )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func filterChip(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private func matchesTypeFilter(_ asset: Asset) -> Bool {
        guard let typeFilter else {
            return true
        }
        return asset.type == typeFilter
    }

    private func matchesOwnerFilter(_ asset: Asset) -> Bool {
        switch ownerFilter {
        case .all:
            return true
        case .unassigned:
            return asset.owner == nil
        case .member(let memberID):
            return asset.owner?.id == memberID
        }
    }

    private func matchesSearch(_ asset: Asset) -> Bool {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else {
            return true
        }

        let fields: [String] = [
            asset.name,
            asset.symbol,
            asset.type.title,
            asset.categoryTag,
            asset.accountPlatformTag,
            asset.owner?.name ?? "",
        ]

        return fields.contains { $0.lowercased().contains(keyword) }
    }

    private func convertedTotal(for assets: [Asset]) -> Double {
        assets.reduce(0) { partialResult, asset in
            partialResult + marketDataCoordinator.convertedToBase(
                amount: asset.marketValue,
                from: asset.currencyCode
            )
        }
    }

    private func displayMemberRelation(_ relation: String) -> String {
        let clean = relation.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty || clean == "家庭成员" || clean == "Family Member" {
            return AppLocalizer.string("member.defaultRelation")
        }
        return relation
    }

    private func deleteAssets(at offsets: IndexSet) {
        let ids = offsets.map { filteredSortedAssets[$0].id }
        for id in ids {
            guard let asset = assets.first(where: { $0.id == id }) else {
                continue
            }
            modelContext.delete(asset)
        }
        try? modelContext.save()
    }

    private func ensureHousehold() -> Household? {
        if let household = households.first {
            return household
        }

        let household = Household(name: "Our Household")
        modelContext.insert(household)
        try? modelContext.save()
        return household
    }
}

private struct AssetDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Member.createdAt) private var members: [Member]
    @Query(sort: \Household.createdAt) private var households: [Household]

    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = "USD"

    @ObservedObject var marketDataCoordinator: MarketDataCoordinator
    let asset: Asset

    @State private var showEditSheet = false

    var body: some View {
        List {
            Section(AppLocalizer.string("assets.detail.section.info")) {
                detailRow(AppLocalizer.string("assets.detail.name"), asset.name)
                detailRow(AppLocalizer.string("assets.detail.type"), asset.type.title)
                detailRow(AppLocalizer.string("assets.detail.valuation"), asset.valuationMode.title)
                detailRow(AppLocalizer.string("assets.detail.owner"), asset.owner?.name ?? AppLocalizer.string("common.unassigned"))

                if !asset.symbol.isEmpty {
                    detailRow(AppLocalizer.string("assets.detail.symbol"), asset.symbol)
                }

                if asset.type == .stock {
                    detailRow(AppLocalizer.string("assets.detail.market"), asset.market.title)
                }

                if asset.quantity > 0 {
                    detailRow(
                        AppLocalizer.string("assets.detail.quantity"),
                        asset.quantity.formatted(.number.precision(.fractionLength(0 ... 4)))
                    )
                }
            }

            Section(AppLocalizer.string("assets.detail.section.amounts")) {
                detailRow(AppLocalizer.string("assets.detail.value"), CurrencyFormatter.string(value: asset.marketValue, currencyCode: asset.currencyCode))

                if asset.currencyCode != normalizedBaseCurrency {
                    detailRow(
                        AppLocalizer.string("assets.detail.converted", normalizedBaseCurrency),
                        CurrencyFormatter.string(value: baseValue, currencyCode: normalizedBaseCurrency)
                    )
                }

                detailRow(
                    AppLocalizer.string("assets.detail.householdShare"),
                    householdPercent.formatted(.percent.precision(.fractionLength(1)))
                )

                if asset.owner == nil {
                    detailRow(AppLocalizer.string("assets.detail.memberShare"), "N/A")
                } else {
                    detailRow(
                        AppLocalizer.string("assets.detail.memberShare"),
                        memberPercent.formatted(.percent.precision(.fractionLength(1)))
                    )
                }
            }

            Section(AppLocalizer.string("assets.detail.section.tags")) {
                detailRow(
                    AppLocalizer.string("assets.detail.tag.category"),
                    asset.categoryTag.isEmpty ? AppLocalizer.string("common.notSet") : asset.categoryTag
                )
                detailRow(
                    AppLocalizer.string("assets.detail.tag.platform"),
                    asset.accountPlatformTag.isEmpty ? AppLocalizer.string("common.notSet") : asset.accountPlatformTag
                )
            }

            if !asset.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section(AppLocalizer.string("assets.detail.section.note")) {
                    Text(asset.note)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(AppLocalizer.string("assets.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            Button {
                showEditSheet = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: floatingActionButtonSize, height: floatingActionButtonSize)
                    .background(Color.accentColor, in: Circle())
                    .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, floatingActionButtonBottomInset)
        }
        .sheet(isPresented: $showEditSheet) {
            if let household = asset.household ?? ensureHousehold() {
                AssetEditorView(
                    mode: .edit,
                    household: household,
                    members: members,
                    asset: asset
                )
            }
        }
    }

    private var normalizedBaseCurrency: String {
        baseCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var baseValue: Double {
        marketDataCoordinator.convertedToBase(
            amount: asset.marketValue,
            from: asset.currencyCode
        )
    }

    private var householdTotalBase: Double {
        let householdAssets = asset.household?.assets ?? households.first?.assets ?? []
        return householdAssets.reduce(0) { partialResult, item in
            partialResult + marketDataCoordinator.convertedToBase(
                amount: item.marketValue,
                from: item.currencyCode
            )
        }
    }

    private var householdPercent: Double {
        householdTotalBase > 0 ? baseValue / householdTotalBase : 0
    }

    private var memberTotalBase: Double {
        (asset.owner?.assets ?? []).reduce(0) { partialResult, item in
            partialResult + marketDataCoordinator.convertedToBase(
                amount: item.marketValue,
                from: item.currencyCode
            )
        }
    }

    private var memberPercent: Double {
        memberTotalBase > 0 ? baseValue / memberTotalBase : 0
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func ensureHousehold() -> Household? {
        if let household = households.first {
            return household
        }

        let household = Household(name: "Our Household")
        modelContext.insert(household)
        try? modelContext.save()
        return household
    }
}

private struct AssetListAddMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let household: Household

    @State private var name = ""
    @State private var relation = ""
    @State private var isPrimary = false

    var body: some View {
        NavigationStack {
            Form {
                TextField(AppLocalizer.string("member.name"), text: $name)
                TextField(AppLocalizer.string("member.relation"), text: $relation)
                Toggle(AppLocalizer.string("member.primary"), isOn: $isPrimary)
            }
            .navigationTitle(AppLocalizer.string("member.add"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalizer.string("common.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalizer.string("common.save")) {
                        saveMember()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveMember() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRelation = relation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanName.isEmpty else {
            return
        }

        let member = Member(
            name: cleanName,
            relation: cleanRelation.isEmpty ? AppLocalizer.string("member.defaultRelation") : cleanRelation,
            isPrimary: isPrimary,
            household: household
        )

        modelContext.insert(member)
        try? modelContext.save()
        dismiss()
    }
}

private enum EditorTagKind {
    case category
    case platform

    var title: String {
        switch self {
        case .category:
            return AppLocalizer.string("settings.tags.category.title")
        case .platform:
            return AppLocalizer.string("settings.tags.platform.title")
        }
    }

    var placeholder: String {
        switch self {
        case .category:
            return AppLocalizer.string("assets.editor.tag.category.placeholder")
        case .platform:
            return AppLocalizer.string("assets.editor.tag.platform.placeholder")
        }
    }
}

private struct AssetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Asset.updatedAt, order: .reverse) private var allAssets: [Asset]

    let mode: AssetEditorMode
    let household: Household
    let members: [Member]
    let asset: Asset?

    @State private var name: String
    @State private var valuationMode: AssetValuationMode
    @State private var selectedType: AssetType
    @State private var symbol: String
    @State private var selectedMarket: StockMarket
    @State private var quantityText: String
    @State private var currencyCode: String
    @State private var marketValueText: String
    @State private var categoryTag: String
    @State private var accountPlatformTag: String
    @State private var note: String
    @State private var selectedOwnerID: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var symbolSuggestions: [SymbolSearchResult] = []
    @State private var isSearchingSymbol = false
    @State private var symbolSearchTask: Task<Void, Never>?
    @State private var quotePrefetchTask: Task<Void, Never>?
    @State private var prefetchedQuotes: [QuoteRequest: QuoteSnapshot] = [:]
    @State private var customCategoryTags: [String] = []
    @State private var customPlatformTags: [String] = []
    @State private var showAddTagAlert = false
    @State private var addTagKind: EditorTagKind = .category
    @State private var addTagDraft = ""
    @State private var preferredNameFromSuggestion = ""
    @State private var preferredNameSymbol = ""

    private let symbolSearchProvider = YahooFinanceProvider()

    init(
        mode: AssetEditorMode,
        household: Household,
        members: [Member],
        asset: Asset?
    ) {
        self.mode = mode
        self.household = household
        self.members = members
        self.asset = asset

        _name = State(initialValue: asset?.name ?? "")
        _valuationMode = State(initialValue: asset?.valuationMode ?? .custom)
        _selectedType = State(initialValue: asset?.type ?? .cash)
        _symbol = State(initialValue: asset?.symbol ?? "")
        _selectedMarket = State(initialValue: asset?.market ?? .us)
        _quantityText = State(initialValue: asset.map { String($0.quantity) } ?? "")
        _currencyCode = State(initialValue: asset?.currencyCode ?? "USD")
        _marketValueText = State(initialValue: asset.map { String($0.marketValue) } ?? "")
        _categoryTag = State(initialValue: asset?.categoryTag ?? "")
        _accountPlatformTag = State(initialValue: asset?.accountPlatformTag ?? "")
        _note = State(initialValue: asset?.note ?? "")
        _selectedOwnerID = State(initialValue: asset?.owner?.id)
        _customCategoryTags = State(initialValue: TagCatalogStore.tags(for: .category))
        _customPlatformTags = State(initialValue: TagCatalogStore.tags(for: .platform))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Asset") {
                    TextField("Name", text: $name)

                    Picker("Valuation", selection: $valuationMode) {
                        ForEach(AssetValuationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Type", selection: $selectedType) {
                        ForEach(availableTypes, id: \.rawValue) { type in
                            Text(type.title).tag(type)
                        }
                    }
                }

                if valuationMode == .standard {
                    Section("Standard Asset") {
                        TextField(
                            selectedType == .stock
                                ? "Search name or ticker (e.g. NVDA / NVIDIA / 0700)"
                                : "Search name or ticker (e.g. BTC / BTC-USD)",
                            text: $symbol
                        )
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                        if selectedType == .stock {
                            Picker("Market", selection: $selectedMarket) {
                                ForEach(StockMarket.allCases) { market in
                                    Text(market.title).tag(market)
                                }
                            }
                        }

                        TextField("Quantity", text: $quantityText)
                            .keyboardType(.decimalPad)
                        Text("Price and total value are automatically calculated from ticker.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if isSearchingSymbol {
                            ProgressView("Searching...")
                                .font(.footnote)
                        }

                        if !symbolSuggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Suggestions")
                                    .font(.subheadline.weight(.semibold))

                                ForEach(symbolSuggestions.prefix(8)) { result in
                                    Button {
                                        applySymbolSuggestion(result)
                                    } label: {
                                        HStack(alignment: .top, spacing: 8) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(result.symbol)
                                                    .font(.subheadline.monospaced())
                                                Text(result.name)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Text(result.exchangeName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                } else {
                    Section("Custom Asset") {
                        Picker("Currency", selection: $currencyCode) {
                            ForEach(customCurrencyOptions, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        TextField("Amount", text: $marketValueText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section(AppLocalizer.string("assets.detail.section.tags")) {
                    tagPickerRow(
                        title: AppLocalizer.string("assets.editor.tag.category"),
                        selection: $categoryTag,
                        options: categoryTagOptions,
                        kind: .category
                    )

                    tagPickerRow(
                        title: AppLocalizer.string("assets.editor.tag.platform"),
                        selection: $accountPlatformTag,
                        options: platformTagOptions,
                        kind: .platform
                    )
                }

                Section("Owner") {
                    Picker("Member", selection: $selectedOwnerID) {
                        Text("Unassigned").tag(Optional<UUID>.none)
                        ForEach(members, id: \.id) { member in
                            Text(member.name).tag(Optional(member.id))
                        }
                    }
                }

                Section("Note") {
                    TextField("Optional", text: $note)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode == .create ? "Add Asset" : "Edit Asset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task {
                            await saveAsset()
                        }
                    }
                    .disabled(isSaving || !canSave)
                }
            }
        }
        .onChange(of: valuationMode) { _, newValue in
            if newValue == .standard && !standardSupportedTypes.contains(selectedType) {
                selectedType = .stock
            }
            if newValue == .custom {
                symbolSuggestions = []
                symbolSearchTask?.cancel()
                isSearchingSymbol = false
            } else {
                triggerSymbolSearch(keyword: symbol)
            }
        }
        .onChange(of: symbol) { _, newValue in
            guard valuationMode == .standard else {
                return
            }
            let normalizedSymbol = newValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            if normalizedSymbol != preferredNameSymbol {
                preferredNameFromSuggestion = ""
                preferredNameSymbol = ""
            }
            triggerSymbolSearch(keyword: newValue)
        }
        .onChange(of: selectedType) { _, _ in
            guard valuationMode == .standard else {
                return
            }
            triggerSymbolSearch(keyword: symbol)
        }
        .onDisappear {
            symbolSearchTask?.cancel()
            quotePrefetchTask?.cancel()
        }
        .alert(AppLocalizer.string("tags.add"), isPresented: $showAddTagAlert) {
            TextField(addTagKind.placeholder, text: $addTagDraft)
            Button(AppLocalizer.string("common.cancel"), role: .cancel) {}
            Button(AppLocalizer.string("common.add")) {
                commitAddedTag()
            }
        } message: {
            Text(AppLocalizer.string("assets.editor.tag.add.hint"))
        }
    }

    private var standardSupportedTypes: [AssetType] {
        [.stock, .crypto]
    }

    private var availableTypes: [AssetType] {
        valuationMode == .standard ? standardSupportedTypes : AssetType.allCases
    }

    private var customCurrencyOptions: [String] {
        var options = MarketDataCoordinator.supportedBaseCurrencies
        let selected = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !selected.isEmpty, !options.contains(selected) {
            options.append(selected)
        }
        return options
    }

    private func triggerSymbolSearch(keyword: String) {
        symbolSearchTask?.cancel()

        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKeyword.count >= 2 else {
            symbolSuggestions = []
            isSearchingSymbol = false
            return
        }

        isSearchingSymbol = true
        let preferredType = selectedType
        let searchKeyword = trimmedKeyword

        symbolSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else {
                return
            }

            do {
                let results = try await symbolSearchProvider.searchSymbols(
                    query: searchKeyword,
                    preferredType: preferredType
                )
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    symbolSuggestions = results
                    isSearchingSymbol = false
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    symbolSuggestions = []
                    isSearchingSymbol = false
                }
            }
        }
    }

    private func applySymbolSuggestion(_ result: SymbolSearchResult) {
        symbolSearchTask?.cancel()
        symbol = result.symbol.uppercased()
        preferredNameFromSuggestion = result.name
        preferredNameSymbol = result.symbol.uppercased()
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = result.name
        }
        selectedType = result.assetType
        selectedMarket = result.market
        if let code = result.currencyCode, !code.isEmpty {
            currencyCode = code
        }
        let request = QuoteRequest(
            symbol: symbol,
            type: selectedType,
            market: selectedType == .stock ? selectedMarket : .global
        )
        prefetchQuote(for: request)
        symbolSuggestions = []
        isSearchingSymbol = false
    }

    private func prefetchQuote(for request: QuoteRequest) {
        quotePrefetchTask?.cancel()

        quotePrefetchTask = Task {
            do {
                let quotes = try await symbolSearchProvider.fetchQuotes(for: [request])
                guard !Task.isCancelled, let quote = quotes.first else {
                    return
                }
                await MainActor.run {
                    prefetchedQuotes[request] = quote
                }
            } catch {
                // Ignore prefetch failures and keep save flow non-blocking.
            }
        }
    }

    private var categoryTagOptions: [String] {
        mergedTagOptions(
            persistedValues: allAssets.map { $0.categoryTag },
            localValues: customCategoryTags,
            selectedValue: categoryTag
        )
    }

    private var platformTagOptions: [String] {
        mergedTagOptions(
            persistedValues: allAssets.map { $0.accountPlatformTag },
            localValues: customPlatformTags,
            selectedValue: accountPlatformTag
        )
    }

    @ViewBuilder
    private func tagPickerRow(
        title: String,
        selection: Binding<String>,
        options: [String],
        kind: EditorTagKind
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .lineLimit(1)

            Spacer()

            Picker("", selection: selection) {
                Text(AppLocalizer.string("common.notSet")).tag("")
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)

            Menu {
                Button(AppLocalizer.string("tags.add")) {
                    startAddTag(kind: kind)
                }

                if !selection.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(AppLocalizer.string("assets.editor.tag.clearSelection"), role: .destructive) {
                        selection.wrappedValue = ""
                    }
                }

                if !options.isEmpty {
                    Divider()
                    ForEach(options, id: \.self) { option in
                        Button(option) {
                            selection.wrappedValue = option
                        }
                    }
                }
            } label: {
                Label(AppLocalizer.string("common.manage"), systemImage: "slider.horizontal.3")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func startAddTag(kind: EditorTagKind) {
        addTagKind = kind
        addTagDraft = ""
        showAddTagAlert = true
    }

    private func commitAddedTag() {
        let cleanTag = addTagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTag.isEmpty else {
            return
        }

        switch addTagKind {
        case .category:
            if !containsTag(cleanTag, in: customCategoryTags) {
                customCategoryTags.append(cleanTag)
            }
            TagCatalogStore.add(cleanTag, kind: .category)
            categoryTag = cleanTag
        case .platform:
            if !containsTag(cleanTag, in: customPlatformTags) {
                customPlatformTags.append(cleanTag)
            }
            TagCatalogStore.add(cleanTag, kind: .platform)
            accountPlatformTag = cleanTag
        }

        addTagDraft = ""
    }

    private func mergedTagOptions(
        persistedValues: [String],
        localValues: [String],
        selectedValue: String
    ) -> [String] {
        var merged = Set<String>()

        for value in persistedValues {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                merged.insert(clean)
            }
        }

        for value in localValues {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                merged.insert(clean)
            }
        }

        let selected = selectedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty {
            merged.insert(selected)
        }

        return merged.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func containsTag(_ target: String, in values: [String]) -> Bool {
        values.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(target) == .orderedSame
        }
    }

    private func inferredDefaultName(for symbol: String) -> String {
        if preferredNameSymbol == symbol {
            let cleanPreferred = preferredNameFromSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanPreferred.isEmpty {
                return cleanPreferred
            }
        }

        if let exactMatch = symbolSuggestions.first(where: {
            $0.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == symbol
        }) {
            let cleanName = exactMatch.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanName.isEmpty {
                return cleanName
            }
        }

        return symbol
    }

    private func defaultCurrency(for type: AssetType, market: StockMarket) -> String {
        if type == .stock && market == .hk {
            return "HKD"
        }
        return "USD"
    }

    private var canSave: Bool {
        if valuationMode == .standard {
            let cleanSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            return !cleanSymbol.isEmpty && (Double(quantityText) ?? 0) > 0
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanName.isEmpty && Double(marketValueText) != nil
    }

    private func saveAsset() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        var cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCategoryTag = categoryTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAccountTag = accountPlatformTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = members.first(where: { $0.id == selectedOwnerID })

        var resolvedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var resolvedMarketValue: Double = 0
        var resolvedSymbol = ""
        var resolvedMarket: StockMarket = .global
        var resolvedQuantity: Double = 0
        var resolvedAutoSync = false
        var resolvedLatestUnitPrice = 0.0
        var resolvedLastQuoteAt: Date?
        var pendingQuoteRequest: QuoteRequest?
        var prefetchedQuoteOnSave: QuoteSnapshot?

        if valuationMode == .standard {
            let cleanSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let quantity = Double(quantityText) ?? 0

            guard !cleanSymbol.isEmpty, quantity > 0 else {
                errorMessage = AppLocalizer.string("assets.editor.error.standard")
                return
            }

            if cleanName.isEmpty {
                cleanName = inferredDefaultName(for: cleanSymbol)
                name = cleanName
            }

            guard !cleanName.isEmpty else {
                errorMessage = AppLocalizer.string("assets.editor.error.nameRequired")
                return
            }

            let market: StockMarket = selectedType == .stock ? selectedMarket : .global
            let request = QuoteRequest(symbol: cleanSymbol, type: selectedType, market: market)
            resolvedSymbol = cleanSymbol
            resolvedMarket = market
            resolvedQuantity = quantity
            resolvedAutoSync = true
            resolvedCurrency = resolvedCurrency.isEmpty ? defaultCurrency(for: selectedType, market: market) : resolvedCurrency
            pendingQuoteRequest = request
            prefetchedQuoteOnSave = prefetchedQuotes[request]

            if let prefetchedQuote = prefetchedQuoteOnSave {
                resolvedLatestUnitPrice = prefetchedQuote.unitPrice
                resolvedLastQuoteAt = prefetchedQuote.asOf
                resolvedCurrency = prefetchedQuote.currencyCode
                resolvedMarketValue = prefetchedQuote.unitPrice * quantity
            }

            if let asset {
                let previousSymbol = asset.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if resolvedLatestUnitPrice == 0, previousSymbol == cleanSymbol, asset.latestUnitPrice > 0 {
                    resolvedLatestUnitPrice = asset.latestUnitPrice
                    resolvedLastQuoteAt = asset.lastQuoteAt
                    resolvedCurrency = asset.currencyCode
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .uppercased()
                    resolvedMarketValue = asset.latestUnitPrice * quantity
                }
            }
        } else {
            guard let value = Double(marketValueText) else {
                errorMessage = AppLocalizer.string("assets.editor.error.customAmount")
                return
            }
            guard !cleanName.isEmpty else {
                errorMessage = AppLocalizer.string("assets.editor.error.nameRequired")
                return
            }
            resolvedCurrency = resolvedCurrency.isEmpty ? "USD" : resolvedCurrency
            resolvedMarketValue = value
        }

        let targetAsset: Asset

        if let asset {
            asset.name = cleanName
            asset.type = selectedType
            asset.valuationMode = valuationMode
            asset.symbol = resolvedSymbol
            asset.market = resolvedMarket
            asset.quantity = resolvedQuantity
            asset.autoSyncPrice = resolvedAutoSync
            asset.latestUnitPrice = resolvedLatestUnitPrice
            asset.lastQuoteAt = resolvedLastQuoteAt
            asset.currencyCode = resolvedCurrency
            asset.marketValue = resolvedMarketValue
            asset.categoryTag = cleanCategoryTag
            asset.accountPlatformTag = cleanAccountTag
            asset.note = cleanNote
            asset.owner = owner
            asset.household = household
            asset.updatedAt = .now
            targetAsset = asset
        } else {
            let newAsset = Asset(
                name: cleanName,
                type: selectedType,
                valuationMode: valuationMode,
                symbol: resolvedSymbol,
                market: resolvedMarket,
                quantity: resolvedQuantity,
                autoSyncPrice: resolvedAutoSync,
                latestUnitPrice: resolvedLatestUnitPrice,
                lastQuoteAt: resolvedLastQuoteAt,
                categoryTag: cleanCategoryTag,
                accountPlatformTag: cleanAccountTag,
                currencyCode: resolvedCurrency,
                marketValue: resolvedMarketValue,
                note: cleanNote,
                updatedAt: .now,
                owner: owner,
                household: household
            )
            modelContext.insert(newAsset)
            targetAsset = newAsset
        }

        do {
            try modelContext.save()
        } catch {
            errorMessage = AppLocalizer.string("assets.editor.error.save", error.localizedDescription)
            return
        }

        dismiss()

        guard let pendingQuoteRequest else {
            return
        }

        Task {
            await refreshQuoteAfterSave(
                for: targetAsset,
                request: pendingQuoteRequest,
                prefetchedQuote: prefetchedQuoteOnSave
            )
        }
    }

    @MainActor
    private func refreshQuoteAfterSave(
        for asset: Asset,
        request: QuoteRequest,
        prefetchedQuote: QuoteSnapshot?
    ) async {
        guard asset.valuationMode == .standard else {
            return
        }
        guard asset.quantity > 0 else {
            return
        }

        if let prefetchedQuote {
            applyQuote(prefetchedQuote, to: asset)
            try? modelContext.save()
            return
        }

        if let cachedQuote = prefetchedQuotes[request] {
            applyQuote(cachedQuote, to: asset)
            try? modelContext.save()
            return
        }

        do {
            let quotes = try await symbolSearchProvider.fetchQuotes(for: [request])
            guard let quote = quotes.first else {
                return
            }

            prefetchedQuotes[request] = quote
            applyQuote(quote, to: asset)
            try? modelContext.save()
        } catch {
            // Keep local save successful even if quote refresh fails.
        }
    }

    private func applyQuote(_ quote: QuoteSnapshot, to asset: Asset) {
        asset.latestUnitPrice = quote.unitPrice
        asset.lastQuoteAt = quote.asOf
        asset.currencyCode = quote.currencyCode
        asset.marketValue = quote.unitPrice * asset.quantity
        asset.updatedAt = .now
    }
}
