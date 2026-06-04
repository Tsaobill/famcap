import SwiftData
import SwiftUI

private enum ManagedTagKind {
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

    var emptyDescription: String {
        switch self {
        case .category:
            return AppLocalizer.string("settings.tags.category.empty")
        case .platform:
            return AppLocalizer.string("settings.tags.platform.empty")
        }
    }

    var catalogKind: TagCatalogKind {
        switch self {
        case .category:
            return .category
        case .platform:
            return .platform
        }
    }
}

private struct ManagedTagItem: Identifiable {
    let kind: ManagedTagKind
    let value: String
    let count: Int

    var id: String { "\(kind.title)|\(value)" }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Household.createdAt) private var households: [Household]
    @Query(sort: \Asset.updatedAt, order: .reverse) private var assets: [Asset]
    @Query(sort: \NetWorthSnapshot.capturedAt, order: .reverse) private var snapshots: [NetWorthSnapshot]
    @Query(sort: \Member.createdAt) private var members: [Member]

    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = "USD"
    @AppStorage("appLanguageCode") private var appLanguageCode = AppLanguage.system.rawValue

    @State private var showNearbySyncSheet = false

    private let supportedBaseCurrencies = MarketDataCoordinator.supportedBaseCurrencies

    var body: some View {
        NavigationStack {
            List {
                Section(AppLocalizer.string("settings.baseCurrency.section")) {
                    Picker(AppLocalizer.string("settings.baseCurrency.title"), selection: $baseCurrencyCode) {
                        ForEach(supportedBaseCurrencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(AppLocalizer.string("settings.baseCurrency.hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(AppLocalizer.string("settings.language.section")) {
                    Picker(AppLocalizer.string("settings.language.title"), selection: $appLanguageCode) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title)
                                .tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(AppLocalizer.string("settings.language.hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(AppLocalizer.string("settings.tags.section")) {
                    NavigationLink {
                        TagManagementView(kind: .category)
                    } label: {
                        settingsEntryRow(
                            title: AppLocalizer.string("settings.tags.category.title"),
                            subtitle: AppLocalizer.string("settings.count.items", categoryTagItems.count)
                        )
                    }

                    NavigationLink {
                        TagManagementView(kind: .platform)
                    } label: {
                        settingsEntryRow(
                            title: AppLocalizer.string("settings.tags.platform.title"),
                            subtitle: AppLocalizer.string("settings.count.items", platformTagItems.count)
                        )
                    }
                }

                Section(AppLocalizer.string("settings.members.section")) {
                    NavigationLink {
                        MemberManagementView()
                    } label: {
                        settingsEntryRow(
                            title: AppLocalizer.string("settings.members.title"),
                            subtitle: AppLocalizer.string("settings.count.people", members.count)
                        )
                    }
                }

                Section(AppLocalizer.string("settings.sync.section")) {
                    Button {
                        if ensureHousehold() != nil {
                            showNearbySyncSheet = true
                        }
                    } label: {
                        Label(AppLocalizer.string("nearby.title"), systemImage: "dot.radiowaves.left.and.right")
                    }

                    Text(AppLocalizer.string("settings.sync.hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(AppLocalizer.string("settings.snapshots.section")) {
                    NavigationLink {
                        SnapshotListView()
                    } label: {
                        settingsEntryRow(
                            title: AppLocalizer.string("settings.snapshots.title"),
                            subtitle: AppLocalizer.string("settings.count.records", snapshots.count)
                        )
                    }
                }
            }
            .navigationTitle(AppLocalizer.string("tab.me"))
        }
        .sheet(isPresented: $showNearbySyncSheet) {
            if let household = households.first {
                NearbySyncSheetView(household: household)
            }
        }
    }

    @ViewBuilder
    private func settingsEntryRow(title: String, subtitle: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var categoryTagItems: [ManagedTagItem] {
        buildTagItems(kind: .category)
    }

    private var platformTagItems: [ManagedTagItem] {
        buildTagItems(kind: .platform)
    }

    private func buildTagItems(kind: ManagedTagKind) -> [ManagedTagItem] {
        let usageValues: [String] = assets.map { asset in
            switch kind {
            case .category:
                return asset.categoryTag.trimmingCharacters(in: .whitespacesAndNewlines)
            case .platform:
                return asset.accountPlatformTag.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let usage = Dictionary(grouping: usageValues.filter { !$0.isEmpty }, by: { $0 })
        let catalogTags = TagCatalogStore.tags(for: kind.catalogKind)

        var allTags = Set(usage.keys)
        allTags.formUnion(catalogTags)

        return allTags
            .map { key in
                ManagedTagItem(kind: kind, value: key, count: usage[key]?.count ?? 0)
            }
            .sorted { left, right in
                if left.count == right.count {
                    return left.value.localizedCaseInsensitiveCompare(right.value) == .orderedAscending
                }
                return left.count > right.count
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

private struct TagManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Asset.updatedAt, order: .reverse) private var assets: [Asset]

    let kind: ManagedTagKind

    @State private var showRenameTagAlert = false
    @State private var renamingOriginalValue = ""
    @State private var renamingDraftValue = ""
    @State private var showAddTagAlert = false
    @State private var addTagDraftValue = ""

    var body: some View {
        List {
            if tagItems.isEmpty {
                Text(kind.emptyDescription)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tagItems) { item in
                    HStack {
                        Text(item.value)
                        Spacer()
                        Text("\(item.count)")
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(AppLocalizer.string("tags.rename.action")) {
                            startRenameTag(item.value)
                        }
                        .tint(.blue)

                        Button(AppLocalizer.string("tags.clear.action"), role: .destructive) {
                            clearTag(item.value)
                        }
                    }
                }
            }
        }
        .navigationTitle(kind.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addTagDraftValue = ""
                    showAddTagAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(AppLocalizer.string("tags.rename.title"), isPresented: $showRenameTagAlert) {
            TextField(AppLocalizer.string("tags.name"), text: $renamingDraftValue)
            Button(AppLocalizer.string("common.cancel"), role: .cancel) {}
            Button(AppLocalizer.string("common.save")) {
                renameTag()
            }
        } message: {
            Text(AppLocalizer.string("tags.rename.message", renamingOriginalValue))
        }
        .alert(AppLocalizer.string("tags.add"), isPresented: $showAddTagAlert) {
            TextField(AppLocalizer.string("tags.name"), text: $addTagDraftValue)
            Button(AppLocalizer.string("common.cancel"), role: .cancel) {}
            Button(AppLocalizer.string("common.add")) {
                addTag()
            }
        } message: {
            Text(AppLocalizer.string("tags.add.message"))
        }
    }

    private var tagItems: [ManagedTagItem] {
        let usageValues: [String] = assets.map { asset in
            switch kind {
            case .category:
                return asset.categoryTag.trimmingCharacters(in: .whitespacesAndNewlines)
            case .platform:
                return asset.accountPlatformTag.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let usage = Dictionary(grouping: usageValues.filter { !$0.isEmpty }, by: { $0 })
        let catalogTags = TagCatalogStore.tags(for: kind.catalogKind)

        var allTags = Set(usage.keys)
        allTags.formUnion(catalogTags)

        return allTags
            .map { key in
                ManagedTagItem(kind: kind, value: key, count: usage[key]?.count ?? 0)
            }
            .sorted { left, right in
                if left.count == right.count {
                    return left.value.localizedCaseInsensitiveCompare(right.value) == .orderedAscending
                }
                return left.count > right.count
            }
    }

    private func addTag() {
        let clean = addTagDraftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return
        }

        TagCatalogStore.add(clean, kind: kind.catalogKind)
    }

    private func startRenameTag(_ value: String) {
        renamingOriginalValue = value
        renamingDraftValue = value
        showRenameTagAlert = true
    }

    private func renameTag() {
        let newValue = renamingDraftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !renamingOriginalValue.isEmpty, !newValue.isEmpty else {
            return
        }

        for asset in assets {
            switch kind {
            case .category:
                if asset.categoryTag == renamingOriginalValue {
                    asset.categoryTag = newValue
                    asset.updatedAt = .now
                }
            case .platform:
                if asset.accountPlatformTag == renamingOriginalValue {
                    asset.accountPlatformTag = newValue
                    asset.updatedAt = .now
                }
            }
        }

        TagCatalogStore.rename(oldValue: renamingOriginalValue, newValue: newValue, kind: kind.catalogKind)
        try? modelContext.save()
    }

    private func clearTag(_ value: String) {
        guard !value.isEmpty else {
            return
        }

        for asset in assets {
            switch kind {
            case .category:
                if asset.categoryTag == value {
                    asset.categoryTag = ""
                    asset.updatedAt = .now
                }
            case .platform:
                if asset.accountPlatformTag == value {
                    asset.accountPlatformTag = ""
                    asset.updatedAt = .now
                }
            }
        }

        TagCatalogStore.remove(value, kind: kind.catalogKind)
        try? modelContext.save()
    }
}

private struct MemberManagementView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Member.createdAt) private var members: [Member]
    @Query(sort: \Household.createdAt) private var households: [Household]

    @State private var showAddSheet = false
    @State private var editingMemberID: UUID?

    var body: some View {
        List {
            if members.isEmpty {
                Text(AppLocalizer.string("members.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(members, id: \.id) { member in
                    Button {
                        editingMemberID = member.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(member.name)
                                        .font(.body.weight(.semibold))
                                    if member.isPrimary {
                                        Text(AppLocalizer.string("member.primary"))
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.2), in: Capsule())
                                    }
                                }

                                Text(displayMemberRelation(member.relation))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteMembers)
            }
        }
        .navigationTitle(AppLocalizer.string("settings.members.section"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            if let household = ensureHousehold() {
                MemberEditorView(mode: .create, household: household)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { editingMemberID != nil },
                set: { isPresented in
                    if !isPresented {
                        editingMemberID = nil
                    }
                }
            )
        ) {
            if let editingMemberID,
               let member = members.first(where: { $0.id == editingMemberID }),
               let household = member.household ?? ensureHousehold()
            {
                MemberEditorView(mode: .edit(member), household: household)
            }
        }
    }

    private func deleteMembers(at offsets: IndexSet) {
        for offset in offsets {
            modelContext.delete(members[offset])
        }
        try? modelContext.save()
    }

    private func displayMemberRelation(_ relation: String) -> String {
        let clean = relation.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty || clean == "家庭成员" || clean == "Family Member" {
            return AppLocalizer.string("member.defaultRelation")
        }
        return relation
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

private enum MemberEditorMode {
    case create
    case edit(Member)
}

private struct MemberEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Member.createdAt) private var allMembers: [Member]

    let mode: MemberEditorMode
    let household: Household

    @State private var name: String
    @State private var relation: String
    @State private var isPrimary: Bool

    init(mode: MemberEditorMode, household: Household) {
        self.mode = mode
        self.household = household

        switch mode {
        case .create:
            _name = State(initialValue: "")
            _relation = State(initialValue: "")
            _isPrimary = State(initialValue: false)
        case .edit(let member):
            _name = State(initialValue: member.name)
            _relation = State(initialValue: member.relation)
            _isPrimary = State(initialValue: member.isPrimary)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(AppLocalizer.string("member.name"), text: $name)
                TextField(AppLocalizer.string("member.relation"), text: $relation)
                Toggle(AppLocalizer.string("member.primary"), isOn: $isPrimary)
            }
            .navigationTitle(modeTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalizer.string("common.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalizer.string("common.save")) {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var modeTitle: String {
        switch mode {
        case .create:
            return AppLocalizer.string("member.add")
        case .edit:
            return AppLocalizer.string("member.edit")
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRelation = relation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanName.isEmpty else {
            return
        }

        if isPrimary {
            for item in allMembers where item.id != editingMemberID {
                if item.isPrimary {
                    item.isPrimary = false
                }
            }
        }

        switch mode {
        case .create:
            let member = Member(
                name: cleanName,
                relation: cleanRelation.isEmpty ? AppLocalizer.string("member.defaultRelation") : cleanRelation,
                isPrimary: isPrimary,
                household: household
            )
            modelContext.insert(member)
        case .edit(let member):
            member.name = cleanName
            member.relation = cleanRelation.isEmpty ? AppLocalizer.string("member.defaultRelation") : cleanRelation
            member.isPrimary = isPrimary
            member.household = household
        }

        try? modelContext.save()
        dismiss()
    }

    private var editingMemberID: UUID? {
        switch mode {
        case .create:
            return nil
        case .edit(let member):
            return member.id
        }
    }
}

private struct SnapshotListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NetWorthSnapshot.capturedAt, order: .reverse) private var snapshots: [NetWorthSnapshot]

    var body: some View {
        List {
            if snapshots.isEmpty {
                Text(AppLocalizer.string("settings.snapshots.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshots, id: \.id) { snapshot in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(CurrencyFormatter.string(value: snapshot.totalValue, currencyCode: snapshot.baseCurrencyCode))
                                .font(.subheadline.monospacedDigit())
                        }

                        Text(
                            AppLocalizer.string(
                                "settings.snapshots.household",
                                String(snapshot.householdID.uuidString.prefix(8)),
                                snapshot.baseCurrencyCode
                            )
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: deleteSnapshots)
            }
        }
        .navigationTitle(AppLocalizer.string("settings.snapshots.title"))
    }

    private func deleteSnapshots(at offsets: IndexSet) {
        for offset in offsets {
            modelContext.delete(snapshots[offset])
        }
        try? modelContext.save()
    }
}
