import SwiftData
import SwiftUI

struct MembersView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Member.createdAt) private var members: [Member]
    @Query(sort: \Household.createdAt) private var households: [Household]

    @State private var showAddMember = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(members, id: \.id) { member in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(member.name)
                                .font(.headline)
                            if member.isPrimary {
                                Text("Primary")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.2), in: Capsule())
                            }
                        }

                        Text(member.relation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(CurrencyFormatter.string(value: member.totalValue, currencyCode: "USD"))
                            .font(.subheadline.monospacedDigit())
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteMembers)
            }
            .navigationTitle("Members")
            .toolbar {
                Button {
                    showAddMember = true
                } label: {
                    Label("Add Member", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddMember) {
            if let household = ensureHousehold() {
                AddMemberView(household: household)
            }
        }
    }

    private func deleteMembers(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(members[index])
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

private struct AddMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let household: Household

    @State private var name = ""
    @State private var relation = ""
    @State private var isPrimary = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Relation", text: $relation)
                Toggle("Primary Member", isOn: $isPrimary)
            }
            .navigationTitle("Add Member")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
            relation: cleanRelation.isEmpty ? "Family" : cleanRelation,
            isPrimary: isPrimary,
            household: household
        )

        modelContext.insert(member)
        try? modelContext.save()
        dismiss()
    }
}
