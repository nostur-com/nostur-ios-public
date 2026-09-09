import Foundation
import NostrEssentials

/// Read-only wallet requests share the existing NWC relay and response parser.
/// Continuations and request state belong to the main actor, never a Core Data queue.
@MainActor
final class NWCWalletClient {
    static let shared = NWCWalletClient()

    struct Connection {
        let id: String
        let walletPubkey: String
        let pubkey: String
        let secret: String
        let relay: String
        let methods: Set<String>

        static func current() -> Connection? {
            let id = SettingsStore.shared.activeNWCconnectionId
            guard SettingsStore.shared.nwcReady, !id.isEmpty,
                  let connection = NWCConnection.fetchConnection(id, context: DataProvider.shared().viewContext),
                  let secret = connection.privateKey else { return nil }
            return Connection(id: id, walletPubkey: connection.walletPubkey, pubkey: connection.pubkey,
                              secret: secret, relay: connection.relay,
                              methods: Set(connection.methods.split(separator: " ").map(String.init)))
        }
    }

    struct Capabilities {
        let methods: Set<String>
        let encryption: String
    }

    enum Failure: LocalizedError {
        case timeout, disconnected, invalidResponse, encryption
        case wallet(String)
        var errorDescription: String? {
            switch self {
            case .timeout: return "The wallet did not respond. Check your connection and try again."
            case .disconnected: return "The wallet connection changed. Please refresh."
            case .invalidResponse: return "The wallet returned an invalid response."
            case .encryption: return "The wallet does not support a compatible encryption method."
            case .wallet(let message): return message
            }
        }
    }

    private struct Pending {
        let connection: Connection
        let method: String
        let continuation: CheckedContinuation<NWCResponse.NWCResponseResult, Error>
    }
    private let activeConnectionId: () -> String
    private let publish: (NEvent) -> Void
    private let subscribe: (String) -> Void
    private let timeoutNanoseconds: UInt64

    init(activeConnectionId: @escaping () -> String = { SettingsStore.shared.activeNWCconnectionId },
         publish: @escaping (NEvent) -> Void = { Unpublisher.shared.publishNow($0) },
         subscribe: @escaping (String) -> Void = { req($0, activeSubscriptionId: "NWC") },
         timeoutNanoseconds: UInt64 = 20 * NSEC_PER_SEC) {
        self.activeConnectionId = activeConnectionId
        self.publish = publish
        self.subscribe = subscribe
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    // Info events are replaceable public service capabilities. The relay parser
    // deduplicates their event IDs, so a second discovery cannot await replay.
    private var capabilitiesByWallet: [String: Capabilities] = [:]
    private var pending: [String: Pending] = [:]
    private var discovery: [UUID: (Connection, CheckedContinuation<Capabilities, Error>)] = [:]

    func discover(_ connection: Connection) async throws -> Capabilities {
        try Task.checkCancellation()
        guard connection.id == activeConnectionId() else { throw Failure.disconnected }
        if let capabilities = capabilitiesByWallet[connection.walletPubkey] { return capabilities }
        let token = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                discovery[token] = (connection, continuation)
                // Keep payment responses subscribed while requesting the wallet's info event.
                let message = """
                ["REQ","NWC",{"authors":["\(connection.walletPubkey)"],"kinds":[13194],"limit":1},{"authors":["\(connection.walletPubkey)"],"#p":["\(connection.pubkey)"],"kinds":[23195]}]
                """
                subscribe(message)
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: self?.timeoutNanoseconds ?? 20 * NSEC_PER_SEC)
                    self?.discovery.removeValue(forKey: token)?.1.resume(throwing: Failure.timeout)
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.discovery.removeValue(forKey: token)?.1.resume(throwing: CancellationError())
            }
        }
    }

    func receiveInfo(walletPubkey: String, methods: String, encryption: String?) {
        let modes = Set((encryption ?? "nip04").split(separator: " ").map(String.init))
        let selected = modes.contains("nip44_v2") ? "nip44_v2" : modes.contains("nip04") ? "nip04" : nil
        let capabilities = selected.map {
            Capabilities(methods: Set(methods.split(separator: " ").map(String.init)), encryption: $0)
        }
        capabilitiesByWallet[walletPubkey] = capabilities
        for (token, item) in discovery where item.0.walletPubkey == walletPubkey {
            discovery.removeValue(forKey: token)
            guard item.0.id == activeConnectionId() else {
                item.1.resume(throwing: Failure.disconnected)
                continue
            }
            if let capabilities {
                item.1.resume(returning: capabilities)
            } else {
                item.1.resume(throwing: Failure.encryption)
            }
        }
    }

    func request(_ method: String, params: NWCRequest.NWCParams = .init(), connection: Connection,
                 encryption: String) async throws -> NWCResponse.NWCResponseResult {
        // Encryption/signing is independent of managed objects and the importer.
        let event = try await Task.detached(priority: .userInitiated) {
            let keys = try Keys(privateKeyHex: connection.secret)
            let data = try JSONEncoder().encode(NWCRequest(method: method, params: params))
            let content = String(decoding: data, as: UTF8.self)
            let encrypted = encryption == "nip44_v2"
                ? Keys.encryptDirectMessageContent44(withPrivatekey: connection.secret, pubkey: connection.walletPubkey, content: content)
                : Keys.encryptDirectMessageContent(withPrivatekey: connection.secret, pubkey: connection.walletPubkey, content: content)
            guard let encrypted else { throw Failure.encryption }
            var event = NEvent(content: encrypted)
            event.kind = .nwcRequest
            event.tags = [NostrTag(["p", connection.walletPubkey]), NostrTag(["encryption", encryption]),
                          NostrTag(["expiration", String(Int(Date().timeIntervalSince1970) + 30)])]
            return try event.sign(keys)
        }.value
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard connection.id == activeConnectionId() else { throw Failure.disconnected }
            return try await withCheckedThrowingContinuation { continuation in
                pending[event.id] = Pending(connection: connection, method: method, continuation: continuation)
                subscribe(RM.getNWCResponses(pubkey: connection.pubkey, walletPubkey: connection.walletPubkey, subscriptionId: "NWC"))
                publish(event)
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: self?.timeoutNanoseconds ?? 20 * NSEC_PER_SEC)
                    self?.pending.removeValue(forKey: event.id)?.continuation.resume(throwing: Failure.timeout)
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.pending.removeValue(forKey: event.id)?.continuation.resume(throwing: CancellationError())
            }
        }
    }

    /// Sends the first authenticated request so wallet services can mark a newly
    /// imported connection as used. Setup does not wait for the response.
    func acknowledgeConnection(_ connection: Connection, encryption: String) async throws {
        try Task.checkCancellation()
        guard connection.id == activeConnectionId() else { throw Failure.disconnected }
        let event = try await makeRequestEvent(
            method: "get_info",
            params: .init(),
            connection: connection,
            encryption: encryption
        )
        publish(event)
    }

    private func makeRequestEvent(method: String, params: NWCRequest.NWCParams,
                                  connection: Connection, encryption: String) async throws -> NEvent {
        try await Task.detached(priority: .userInitiated) {
            let keys = try Keys(privateKeyHex: connection.secret)
            let data = try JSONEncoder().encode(NWCRequest(method: method, params: params))
            let content = String(decoding: data, as: UTF8.self)
            let encrypted = encryption == "nip44_v2"
                ? Keys.encryptDirectMessageContent44(withPrivatekey: connection.secret, pubkey: connection.walletPubkey, content: content)
                : Keys.encryptDirectMessageContent(withPrivatekey: connection.secret, pubkey: connection.walletPubkey, content: content)
            guard let encrypted else { throw Failure.encryption }
            var event = NEvent(content: encrypted)
            event.kind = .nwcRequest
            event.tags = [NostrTag(["p", connection.walletPubkey]), NostrTag(["encryption", encryption]),
                          NostrTag(["expiration", String(Int(Date().timeIntervalSince1970) + 30)])]
            return try event.sign(keys)
        }.value
    }

    func receive(_ response: NWCResponse, requestId: String, walletPubkey: String) {
        guard let item = pending[requestId], item.connection.walletPubkey == walletPubkey else { return }
        guard response.result_type == item.method || (response.result_type == nil && response.error != nil) else { return }
        pending.removeValue(forKey: requestId)
        guard item.connection.id == activeConnectionId() else {
            item.continuation.resume(throwing: Failure.disconnected)
            return
        }
        if let error = response.error {
            item.continuation.resume(throwing: Failure.wallet("\(error.message) (\(error.code))"))
        } else if let result = response.result {
            item.continuation.resume(returning: result)
        } else {
            item.continuation.resume(throwing: Failure.invalidResponse)
        }
    }
}
