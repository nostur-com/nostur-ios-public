//
//  PostMenuFunctions.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/08/2025.
//

import Foundation
import NostrEssentials

@MainActor
func pinToProfile(_ nrPost: NRPost) async throws {
    // check logged in account == nrPost.pubkey
    guard let account = account(), nrPost.pubkey == account.publicKey else { return }
    
    let rawSource = await withBgContext { _ in
        return nrPost.event?.toNEvent().eventJson()
    }
    
    guard let rawSource else { return }
    
    let latestPinned = NEvent(content: rawSource, kind: .latestPinned, tags: [
        NostrTag(["e", nrPost.id]),
        NostrTag(["k", nrPost.kind.description])
    ])
    
    let latestPinnedSigned = try await sign(nEvent: latestPinned, accountPubkey: account.publicKey)
    DispatchQueue.main.async {
        Unpublisher.shared.publishNow(latestPinnedSigned)
    }
    
    sendNotification(.didPinPost, PinPostInfo(pinEvent: latestPinnedSigned, pinnedPost: nrPost))
}

struct PinPostInfo: Identifiable {
    var id: String { pinEvent.id + pinnedPost.id }
    let pinEvent: NEvent
    let pinnedPost: NRPost
}

@MainActor
func addToHighlights(_ postToPin: NRPost) async throws {
    // check logged in account == nrPost.pubkey
    guard let account = account(), postToPin.pubkey == account.publicKey else { return }
    let accountPubkey = account.publicKey
    
    _ = try? await relayReq(Filters(authors: [account.publicKey], kinds: [10001]), accountPubkey: accountPubkey)
    
    // Fetch from DB
    let highlightsListNEvent: Nostur.NEvent? = await withBgContext { _ in
        let highlightsListEvent: Nostur.Event? = Event.fetchReplacableEvent(10001, pubkey: accountPubkey)
        return highlightsListEvent?.toNEvent()
    }
    
    if let highlightsListNEvent { // Add (but no duplicates)
        if highlightsListNEvent.fastTags.first(where: { $0.1 == postToPin.id }) == nil {
            var updatedHighlightsListNEvent = highlightsListNEvent
            updatedHighlightsListNEvent.tags.append(NostrTag(["e", postToPin.id]))
            
            // sign
            let signedEvent = try await sign(nEvent: updatedHighlightsListNEvent, accountPubkey: accountPubkey)
            
            // publish and save
            L.sockets.debug("Going to publish updated highlights list")
            DispatchQueue.main.async {
                Unpublisher.shared.publishNow(signedEvent)
            }
        }
        else {
            L.sockets.debug("Highlights list already contains pinned post")
        }
    }
    else { // Create
        var newHighlightsList = NEvent(kind: .pinnedList,  tags: [NostrTag(["e", postToPin.id])])

        // sign
        let signedEvent = try await sign(nEvent: newHighlightsList, accountPubkey: accountPubkey)
        
        // publish and save
        L.sockets.debug("Going to publish new highlights list")
        DispatchQueue.main.async {
            Unpublisher.shared.publishNow(signedEvent)
        }
    }
}

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
                            NSecBunkerManager.shared.requestSignature(forEvent: nEvent, usingAccount: account, whenSigned: { signedEvent in
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
