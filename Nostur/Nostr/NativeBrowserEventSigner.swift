import Foundation
import Combine
import NostrEssentials

@MainActor
protocol BrowserCryptoPerforming: AnyObject {
    func perform(_ approval: BrowserCryptoApproval, requestID: UUID,
                 completion: @escaping @MainActor @Sendable (Result<String, BrowserSigningFailure>) -> Void)
    func cancel(_ requestID: UUID)
}

/// Encryption keys and NIP-46 session secrets stay in this native component.
/// Only the requested ciphertext or plaintext crosses back to the browser.
@MainActor
final class NativeBrowserCryptor: BrowserCryptoPerforming {
    private struct Operation {
        let cancellation: NativeSigningCancellation
        var observer: AnyCancellable?
    }
    private var operations: [UUID: Operation] = [:]
    private let queue: DispatchQueue
    private let localKeyProvider: ((String) -> String?)?

    init(queue: DispatchQueue = DispatchQueue(label: "com.nostur.browser.encryption", qos: .userInitiated),
         localKeyProvider: ((String) -> String?)? = nil) {
        self.queue = queue
        self.localKeyProvider = localKeyProvider
    }

    func perform(_ approval: BrowserCryptoApproval, requestID: UUID,
                 completion: @escaping @MainActor @Sendable (Result<String, BrowserSigningFailure>) -> Void) {
        let now = Int64(Date().timeIntervalSince1970)
        guard now >= approval.approvedAt, now - approval.approvedAt <= 15, approval.request.isValid,
              BrowserSigningPolicy.origin(URL(string: approval.origin)) == approval.origin,
              operations[requestID] == nil else { completion(.failure(.unavailable)); return }
        let cancellation = NativeSigningCancellation()
        operations[requestID] = Operation(cancellation: cancellation)
        let account = AccountsState.shared.accounts.first { !$0.isDeleted && $0.publicKey == approval.accountPubkey }
        if let account, account.isNC {
            performRemote(approval, requestID: requestID, account: account, cancellation: cancellation, completion: completion)
            return
        }
        let key: String?
        if let localKeyProvider { key = localKeyProvider(approval.accountPubkey) }
        else { key = account?.privateKey }
        guard let key else { complete(requestID, result: .failure(.unavailable), completion: completion); return }
        queue.async { [weak self] in
            guard !cancellation.isCanceled else { return }
            guard let keys = try? Keys(privateKeyHex: key), keys.publicKeyHex == approval.accountPubkey else {
                DispatchQueue.main.async { self?.complete(requestID, result: .failure(.unavailable), completion: completion) }
                return
            }
            let request = approval.request
            let text: String?
            switch request.method {
            case .nip04Encrypt:
                text = Keys.encryptDirectMessageContent(withPrivatekey: key, pubkey: request.pubkey, content: request.data)
            case .nip04Decrypt:
                text = Keys.decryptDirectMessageContent(withPrivateKey: key, pubkey: request.pubkey, content: request.data)
            case .nip44Encrypt:
                text = Keys.encryptDirectMessageContent44(withPrivatekey: key, pubkey: request.pubkey, content: request.data)
            case .nip44Decrypt:
                text = Keys.decryptDirectMessageContent44(withPrivateKey: key, pubkey: request.pubkey, content: request.data)
            }
            let result = Self.checkedResult(text, method: request.method)
            DispatchQueue.main.async { self?.complete(requestID, result: result, completion: completion) }
        }
    }

    func cancel(_ requestID: UUID) {
        guard let operation = operations.removeValue(forKey: requestID) else { return }
        operation.cancellation.cancel()
        operation.observer?.cancel()
    }

    private func complete(_ id: UUID, result: Result<String, BrowserSigningFailure>,
                          completion: @escaping @MainActor @Sendable (Result<String, BrowserSigningFailure>) -> Void) {
        guard let operation = operations.removeValue(forKey: id), !operation.cancellation.isCanceled else { return }
        operation.observer?.cancel()
        completion(result)
    }

    nonisolated private static func checkedResult(_ text: String?, method: BrowserCryptoMethod) -> Result<String, BrowserSigningFailure> {
        guard let text, text.utf8.count <= (method.encrypts ? 131072 : 65535) else { return .failure(.failed) }
        return .success(text)
    }

    private func performRemote(_ approval: BrowserCryptoApproval, requestID: UUID, account: CloudAccount,
                               cancellation: NativeSigningCancellation,
                               completion: @escaping @MainActor @Sendable (Result<String, BrowserSigningFailure>) -> Void) {
        // For remote accounts privateKey is a transport secret, never the
        // account's encryption key. Send the operation to the configured signer.
        guard let sessionKey = account.privateKey, let keys = try? Keys(privateKeyHex: sessionKey) else {
            complete(requestID, result: .failure(.unavailable), completion: completion)
            return
        }
        let remotePubkey = account.ncRemoteSignerPubkey
        let sessionPubkey = keys.publicKeyHex
        let command = "crypto-browser-" + requestID.uuidString
        let request = approval.request
        let queue = queue
        operations[requestID]?.observer = receiveNotification(.receivedMessage).sink { [weak self] notification in
            guard let message = notification.object as? NXRelayMessage, let event = message.event,
                  event.kind == .ncMessage, event.publicKey == remotePubkey, event.content.utf8.count <= 262144,
                  event.tags.contains(where: { $0.type == "p" && $0.value == sessionPubkey }) else { return }
            queue.async {
                guard !cancellation.isCanceled, (try? event.verified(logInvalidID: false)) == true,
                      let plaintext = Keys.decryptDirectMessageContent44(withPrivateKey: sessionKey, pubkey: remotePubkey, content: event.content)
                        ?? Keys.decryptDirectMessageContent(withPrivateKey: sessionKey, pubkey: remotePubkey, content: event.content),
                      let data = plaintext.data(using: .utf8), data.count <= 262144,
                      let response = try? JSONDecoder().decode(NCResponse.self, from: data), response.id == command else { return }
                let result: Result<String, BrowserSigningFailure> = response.error == nil
                    ? Self.checkedResult(response.result, method: request.method) : .failure(.failed)
                DispatchQueue.main.async { self?.complete(requestID, result: result, completion: completion) }
            }
        }
        queue.async { [weak self] in
            guard !cancellation.isCanceled else { return }
            let rpc = NCRequest(id: command, method: request.method.remoteMethod, params: [request.pubkey, request.data])
            guard let data = try? JSONEncoder().encode(rpc), let plaintext = String(data: data, encoding: .utf8),
                  let encrypted = Keys.encryptDirectMessageContent44(withPrivatekey: sessionKey, pubkey: remotePubkey, content: plaintext) else {
                DispatchQueue.main.async { self?.complete(requestID, result: .failure(.failed), completion: completion) }
                return
            }
            var event = NEvent(content: encrypted)
            event.kind = .ncMessage
            event.tags = [NostrTag(["p", remotePubkey])]
            guard let signed = try? event.sign(keys) else {
                DispatchQueue.main.async { self?.complete(requestID, result: .failure(.failed), completion: completion) }
                return
            }
            DispatchQueue.main.async {
                guard let self, self.operations[requestID] != nil,
                      let account = AccountsState.shared.accounts.first(where: {
                          !$0.isDeleted && $0.isNC && $0.publicKey == approval.accountPubkey && $0.ncRemoteSignerPubkey == remotePubkey
                      }) else { return }
                RemoteSignerManager.shared.sendBrowserCryptoMessage(signed, usingAccount: account, sessionPublicKey: sessionPubkey)
            }
        }
    }
}

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
        guard data.count <= BrowserSigningPolicy.maximumRequestBytes(for: approval.event.kind) + 512 else {
            throw BrowserSigningFailure.failed
        }
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
