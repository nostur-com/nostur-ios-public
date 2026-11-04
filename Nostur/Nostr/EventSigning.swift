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
