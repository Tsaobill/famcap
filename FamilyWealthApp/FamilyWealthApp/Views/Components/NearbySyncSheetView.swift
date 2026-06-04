import MultipeerConnectivity
import SwiftData
import SwiftUI

struct NearbySyncSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let household: Household

    @StateObject private var syncService = NearbySyncService()

    @State private var pendingImportEnvelope: HouseholdSyncEnvelope?
    @State private var showImportAlert = false
    @State private var importSummaryText: String?

    var body: some View {
        NavigationStack {
            List {
                Section("This Device") {
                    Text(syncService.localPeerName)
                        .font(.headline)
                    Text("Nearby sync uses peer-to-peer network only. No iCloud is required.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Connected Devices") {
                    if syncService.connectedPeers.isEmpty {
                        Text("No connected devices.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(syncService.connectedPeers, id: \.displayName) { peer in
                            HStack {
                                Text(peer.displayName)
                                Spacer()
                                Button("Send") {
                                    sendSnapshot(to: peer)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        Button("Send to All Connected") {
                            sendSnapshot()
                        }
                    }
                }

                Section("Nearby Devices") {
                    if discoverablePeers.isEmpty {
                        Text("No nearby devices found yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(discoverablePeers, id: \.displayName) { peer in
                            HStack {
                                Text(peer.displayName)
                                Spacer()
                                Button("Connect") {
                                    syncService.invite(peer)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                if let statusMessage = syncService.statusMessage {
                    Section("Status") {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let importSummaryText {
                    Section("Last Import") {
                        Text(importSummaryText)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Nearby Sync")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            syncService.start()
        }
        .onDisappear {
            syncService.stop()
        }
        .onReceive(syncService.$latestReceivedEnvelope) { newEnvelope in
            guard let newEnvelope else {
                return
            }
            pendingImportEnvelope = newEnvelope
            showImportAlert = true
        }
        .alert(
            "Import Received Snapshot?",
            isPresented: $showImportAlert,
            presenting: pendingImportEnvelope
        ) { envelope in
            Button("Import") {
                importEnvelope(envelope)
            }
            Button("Cancel", role: .cancel) {}
        } message: { envelope in
            Text("From \(envelope.senderName), exported at \(envelope.exportedAt.formatted(date: .numeric, time: .shortened)).")
        }
    }

    private var discoverablePeers: [MCPeerID] {
        syncService.availablePeers
            .filter { peer in !syncService.connectedPeers.contains(where: { $0 == peer }) }
            .sorted { $0.displayName < $1.displayName }
    }

    private func sendSnapshot(to peer: MCPeerID? = nil) {
        let envelope = HouseholdSyncCodec.makeEnvelope(
            from: household,
            senderName: syncService.localPeerName
        )

        do {
            try syncService.send(envelope, to: peer)
        } catch {
            syncService.statusMessage = error.localizedDescription
        }
    }

    private func importEnvelope(_ envelope: HouseholdSyncEnvelope) {
        do {
            let summary = try HouseholdSyncCodec.importEnvelope(
                envelope,
                into: modelContext
            )
            importSummaryText = [
                summary.householdInserted ? "Household inserted" : "Household updated",
                "Members +\(summary.membersInserted) / ~\(summary.membersUpdated)",
                "Assets +\(summary.assetsInserted) / ~\(summary.assetsUpdated)",
            ].joined(separator: " · ")
            syncService.statusMessage = "Import completed."
        } catch {
            syncService.statusMessage = error.localizedDescription
        }
    }
}
