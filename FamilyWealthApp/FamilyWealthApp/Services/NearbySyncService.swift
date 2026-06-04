import Foundation
import MultipeerConnectivity
import UIKit

enum NearbySyncError: LocalizedError {
    case noConnectedPeer

    var errorDescription: String? {
        switch self {
        case .noConnectedPeer:
            return "No connected nearby device."
        }
    }
}

final class NearbySyncService: NSObject, ObservableObject {
    static let serviceType = "fwsyncshare"

    @Published private(set) var availablePeers: [MCPeerID] = []
    @Published private(set) var connectedPeers: [MCPeerID] = []
    @Published private(set) var isRunning = false
    @Published var statusMessage: String?
    @Published var latestReceivedEnvelope: HouseholdSyncEnvelope?

    let localPeerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser

    override init() {
        let localPeerID = MCPeerID(displayName: UIDevice.current.name)
        self.localPeerID = localPeerID
        session = MCSession(
            peer: localPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        advertiser = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: ["app": "FamilyWealth"],
            serviceType: Self.serviceType
        )
        browser = MCNearbyServiceBrowser(
            peer: localPeerID,
            serviceType: Self.serviceType
        )
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    var localPeerName: String {
        localPeerID.displayName
    }

    func start() {
        guard !isRunning else {
            return
        }
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        isRunning = true
        statusMessage = "Nearby sync is active."
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        isRunning = false
        availablePeers = []
        connectedPeers = []
        statusMessage = "Nearby sync stopped."
    }

    func invite(_ peerID: MCPeerID) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
        statusMessage = "Inviting \(peerID.displayName)..."
    }

    func send(_ envelope: HouseholdSyncEnvelope, to peerID: MCPeerID? = nil) throws {
        let payload = try JSONEncoder().encode(envelope)
        let peers: [MCPeerID]

        if let peerID {
            peers = [peerID]
        } else {
            peers = session.connectedPeers
        }

        guard !peers.isEmpty else {
            throw NearbySyncError.noConnectedPeer
        }

        try session.send(payload, toPeers: peers, with: .reliable)
        statusMessage = "Sent household snapshot to \(peers.count) peer(s)."
    }

    private func publishConnectionUpdate() {
        connectedPeers = session.connectedPeers.sorted { $0.displayName < $1.displayName }
    }
}

extension NearbySyncService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext _: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, session)
        DispatchQueue.main.async {
            self.statusMessage = "Accepted invitation from \(peerID.displayName)."
        }
    }
}

extension NearbySyncService: MCNearbyServiceBrowserDelegate {
    func browser(
        _: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo _: [String: String]?
    ) {
        DispatchQueue.main.async {
            guard peerID != self.localPeerID else {
                return
            }
            if !self.availablePeers.contains(peerID) {
                self.availablePeers.append(peerID)
                self.availablePeers.sort { $0.displayName < $1.displayName }
            }
        }
    }

    func browser(_: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.availablePeers.removeAll { $0 == peerID }
        }
    }

    func browser(_: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.statusMessage = error.localizedDescription
        }
    }
}

extension NearbySyncService: MCSessionDelegate {
    func session(_: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.publishConnectionUpdate()
            switch state {
            case .connected:
                self.statusMessage = "\(peerID.displayName) connected."
            case .connecting:
                self.statusMessage = "Connecting to \(peerID.displayName)..."
            case .notConnected:
                self.statusMessage = "\(peerID.displayName) disconnected."
            @unknown default:
                self.statusMessage = "Connection state changed."
            }
        }
    }

    func session(_: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let envelope = try JSONDecoder().decode(HouseholdSyncEnvelope.self, from: data)
            DispatchQueue.main.async {
                self.latestReceivedEnvelope = envelope
                self.statusMessage = "Received sync package from \(peerID.displayName)."
            }
        } catch {
            DispatchQueue.main.async {
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func session(
        _: MCSession,
        didReceive _: InputStream,
        withName _: String,
        fromPeer _: MCPeerID
    ) {}

    func session(
        _: MCSession,
        didStartReceivingResourceWithName _: String,
        fromPeer _: MCPeerID,
        with _: Progress
    ) {}

    func session(
        _: MCSession,
        didFinishReceivingResourceWithName _: String,
        fromPeer _: MCPeerID,
        at _: URL?,
        withError _: Error?
    ) {}
}
