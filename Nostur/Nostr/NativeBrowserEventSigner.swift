import Foundation

enum BrowserSigningFailure: Error, Sendable { case unavailable, failed, canceled, timeout }

@MainActor
protocol BrowserEventSigning: AnyObject {
    func sign(_ approval: BrowserSigningApproval, requestID: UUID,
              completion: @escaping @MainActor @Sendable (Result<BrowserSignedEvent, BrowserSigningFailure>) -> Void)
    func cancel(_ requestID: UUID)
}

/// Key access is confined to this native component. It imports no WebKit APIs,
/// accepts only policy-issued approvals, and returns only a fixed public DTO.
@MainActor
final class NativeBrowserEventSigner: BrowserEventSigning {
    private struct Operation {
        let cancellation: NativeSigningCancellation
        let remoteCommand: String?
    }
    private var operations: [UUID: Operation] = [:]
    private let queue: DispatchQueue
    private let localKeyProvider: ((String) -> String?)?

    init(queue: DispatchQueue = DispatchQueue(label: "com.nostur.browser.native-signing", qos: .userInitiated),
         localKeyProvider: ((String) -> String?)? = nil) {
        self.queue = queue
        self.localKeyProvider = localKeyProvider
    }

    func sign(_ approval: BrowserSigningApproval, requestID: UUID,
              completion: @escaping @MainActor @Sendable (Result<BrowserSignedEvent, BrowserSigningFailure>) -> Void) {
        let now = Int64(Date().timeIntervalSince1970)
        guard now >= approval.approvedAt, now - approval.approvedAt <= 15,
              BrowserSigningPolicy.origin(URL(string: approval.origin)) == approval.origin,
              operations[requestID] == nil else { completion(.failure(.unavailable)); return }
        let cancellation = NativeSigningCancellation()
        if localKeyProvider == nil,
           let account = AccountsState.shared.accounts.first(where: { !$0.isDeleted && $0.publicKey == approval.accountPubkey }), account.isNC {
            let command = "sign-event-browser-\(requestID.uuidString)"
            operations[requestID] = Operation(cancellation: cancellation, remoteCommand: command)
            let queue = queue
            RemoteSignerManager.shared.requestSignature(forEvent: approval.event.nostrEvent(publicKey: approval.accountPubkey), usingAccount: account, requestID: command) { [weak self] signed in
                guard let data = try? JSONEncoder().encode(signed) else { return }
                queue.async {
                    guard !cancellation.isCanceled else { return }
                    let result = Result { try Self.validate(data, approval: approval) }.mapError { _ in BrowserSigningFailure.failed }
                    DispatchQueue.main.async { self?.complete(requestID, result: result, completion: completion) }
                }
            }
            return
        }
        // No managed object, keychain interface or key is passed to the browser.
        let key: String?
        if let localKeyProvider { key = localKeyProvider(approval.accountPubkey) }
        else {
            key = AccountsState.shared.accounts.first(where: { !$0.isDeleted && $0.publicKey == approval.accountPubkey && !$0.isNC })?.privateKey
        }
        guard let key else { completion(.failure(.unavailable)); return }
        operations[requestID] = Operation(cancellation: cancellation, remoteCommand: nil)
        queue.async { [weak self] in
            guard !cancellation.isCanceled else { return }
            let result = Result {
                let event = try localSignNEvent(approval.event.nostrEvent(publicKey: approval.accountPubkey), pk: key)
                return try Self.validate(JSONEncoder().encode(event), approval: approval)
            }.mapError { _ in BrowserSigningFailure.failed }
            guard !cancellation.isCanceled else { return }
            DispatchQueue.main.async { self?.complete(requestID, result: result, completion: completion) }
        }
    }

    func cancel(_ requestID: UUID) {
        guard let operation = operations.removeValue(forKey: requestID) else { return }
        operation.cancellation.cancel()
        if let command = operation.remoteCommand { RemoteSignerManager.shared.cancelSignatureRequest(command) }
    }

    private func complete(_ id: UUID, result: Result<BrowserSignedEvent, BrowserSigningFailure>,
                          completion: @MainActor @Sendable (Result<BrowserSignedEvent, BrowserSigningFailure>) -> Void) {
        guard let operation = operations.removeValue(forKey: id), !operation.cancellation.isCanceled else { return }
        if let command = operation.remoteCommand { RemoteSignerManager.shared.cancelSignatureRequest(command) }
        completion(result)
    }

    nonisolated static func validate(_ data: Data, approval: BrowserSigningApproval) throws -> BrowserSignedEvent {
        guard data.count <= 131072 else { throw BrowserSigningFailure.failed }
        let result = try JSONDecoder().decode(BrowserSignedEvent.self, from: data)
        guard result.matches(approval.event, accountPubkey: approval.accountPubkey),
              try JSONDecoder().decode(NEvent.self, from: data).verified(logInvalidID: false) else { throw BrowserSigningFailure.failed }
        return result
    }
}

/// The lock protects one in-memory flag only; signing and callbacks never run
/// under it, and cancellation never waits for the signing work queue.
final class NativeSigningCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var canceled = false
    var isCanceled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return canceled
    }
    func cancel() {
        lock.lock()
        canceled = true
        lock.unlock()
    }
}

extension BrowserUnsignedEvent {
    func nostrEvent(publicKey: String) -> NEvent {
        NEvent(publicKey: publicKey, createdAt: NTimestamp(timestamp: created_at),
               content: content, kind: NEventKind(id: kind), tags: tags.map(NostrTag.init))
    }
}
