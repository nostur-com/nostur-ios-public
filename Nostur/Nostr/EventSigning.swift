import Foundation
import NostrEssentials
import secp256k1

func sign(nEvent: NEvent, accountPubkey: String) async throws -> NEvent {
    return try await withCheckedThrowingContinuation({ continuation in
        DispatchQueue.main.async {
            do {
                guard let account = AccountsState.shared.accounts.first(where: { $0.publicKey == accountPubkey }) else {
                    throw SignError.accountNotFound
                }
                guard let pk = account.privateKey else { throw SignError.privateKeyMissing }
                if !account.isNC {
                    let signedNEvent = try localSignNEvent(nEvent, pk: pk)
                    continuation.resume(returning: signedNEvent)
                }
                else {
                    var nEvent = nEvent
                    nEvent = nEvent.withId()
                    
                    // Create a timeout task
                    let timeoutTask = Task {
                        try await Task.sleep(nanoseconds: 12 * 1_000_000_000) // 12 seconds
                        throw SignError.timeout
                    }
                    
                    // Create the signature request task
                    let signatureTask = Task {
                        try await withCheckedThrowingContinuation { continuation in
                            RemoteSignerManager.shared.requestSignature(forEvent: nEvent, usingAccount: account, whenSigned: { signedEvent in
                                continuation.resume(returning: signedEvent)
                            })
                        }
                    }
                    
                    // Race between signature and timeout
                    Task {
                        do {
                            let signedEvent = try await signatureTask.value
                            timeoutTask.cancel() // Cancel timeout if signature succeeds
                            continuation.resume(returning: signedEvent)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    })
}

func localSignNEvent(_ nEvent: NEvent, pk: String) throws -> NEvent {
    var nEvent = nEvent
    
    let keys = try Keys(privateKeyHex: pk)
    
    let serializableEvent = NSerializableEvent(publicKey: keys.publicKeyHex, createdAt: nEvent.createdAt, kind: nEvent.kind, tags: nEvent.tags, content: nEvent.content)

    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    let serializedEvent = try! encoder.encode(serializableEvent)
    let sha256Serialized = SHA256.hash(data: serializedEvent)

    let sig = try! keys.signature(for: sha256Serialized)

    guard keys.publicKey.isValidSignature(sig, for: sha256Serialized) else {
        throw SignError.signingFailure
    }

    nEvent.id = String(bytes: sha256Serialized.bytes)
    nEvent.publicKey = keys.publicKeyHex
    nEvent.signature = String(bytes: sig.bytes)
    
    return nEvent
}

@MainActor
func signMinedEvent(_ event: NEvent, account: CloudAccount) async throws -> NEvent {
    try Task.checkCancellation()
    guard account.isFullAccount, !account.isDeleted, event.publicKey == account.publicKey else {
        throw SignError.accountNotFound
    }
    let signed = if account.isNC {
        try await MinedEventSignatureRequest().sign(event, account: account)
    } else {
        try account.signEvent(event)
    }
    try Task.checkCancellation()
    guard !event.id.isEmpty, signed.id == event.id, (try? signed.verified(logInvalidID: false)) == true else {
        throw SignError.signingFailure
    }
    return signed
}

@MainActor
private final class MinedEventSignatureRequest {
    private let id = "sign-event-\(UUID().uuidString)"
    private var pending: CheckedContinuation<NEvent, Error>?

    func sign(_ event: NEvent, account: CloudAccount) async throws -> NEvent {
        let timeout = Task {
            do {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                finish(.failure(SignError.timeout))
            } catch { }
        }
        defer {
            timeout.cancel()
            RemoteSignerManager.shared.cancelSignatureRequest(id)
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                RemoteSignerManager.shared.requestSignature(forEvent: event, usingAccount: account, requestID: id) { [weak self] signed in
                    Task { @MainActor in self?.finish(.success(signed)) }
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<NEvent, Error>) {
        guard let pending else { return }
        self.pending = nil
        pending.resume(with: result)
    }
}

enum SignError: Error, LocalizedError, Equatable {
    
    static func == (lhs: SignError, rhs: SignError) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
    
    case accountNotFound
    case privateKeyMissing
    case signingFailure
    case timeout // bunker signing timeout
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .accountNotFound: return "Account not found."
        case .signingFailure: return "Signing failed."
        case .privateKeyMissing: return "Private key missing."
        case .timeout: return "Timed out."
        case .unknown(let err): return err.localizedDescription
        }
    }
}
