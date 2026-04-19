//
//  NIP05VerificationPipeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/05/2023.
//

import Foundation
import Combine

// Buffer up to 50 pending verifications, check as fast as possible
// while not doing more than 2 simultaneously
// Caches failed request so we don't keep retrying
class NIP05Verifier {
    static let shared = NIP05Verifier()
    private let maxConcurrentRequests:Int = 2
    private let bufferSize: Int = 50
    private var verifySubject = PassthroughSubject<Contact, Never>()
    
    private var cancellables = Set<AnyCancellable>()
    
    public static var fourWeeksAgo = Date.now.addingTimeInterval(-2419200)
    private var decoder = JSONDecoder()
    
    init() {
        verifySubject
            .removeDuplicates()
            .filter { contact in
                contact.nip05 != nil
            }
            .filter { contact in
                return (contact.nip05verifiedAt == nil || (contact.nip05verifiedAt != nil) && (contact.nip05verifiedAt! < Self.fourWeeksAgo))
            }
            .handleEvents(receiveOutput: { [weak self] contact in
                // Namecoin (.bit) verification path — sidecar; does not affect the
                // HTTP pipeline below. Dispatched async so it doesn't block.
                guard let nip05 = contact.nip05?.trimmingCharacters(in: .whitespacesAndNewlines),
                      NamecoinResolver.isNamecoinIdentifier(nip05) else { return }
                self?.verifyNamecoin(contact: contact, nip05: nip05)
            })
            .filter { contact in
                let nip05trimmed = contact.nip05!.trimmingCharacters(in: .whitespacesAndNewlines)
                // Namecoin identifiers are handled in the sidecar above.
                if NamecoinResolver.isNamecoinIdentifier(nip05trimmed) { return false }
                let nip05parts = nip05trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
                return nip05parts.count == 2
            }
            .compactMap({ contact in 
                let nip05trimmed = contact.nip05!.trimmingCharacters(in: .whitespacesAndNewlines)
                let nip05parts = nip05trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
                    
                let domain = String(nip05parts[1])
                let name = String(nip05parts[0])
                
                let nip05url = URL(string: "https://\(domain)/.well-known/nostr.json?name=\(name)")
                
                return NIP05Task(contact: contact, nip05url: nip05url, domain: domain, name: name)
            })
            .filter {
                $0.nip05url != nil
            }
            .buffer(size: bufferSize, prefetch: .byRequest, whenFull: .dropOldest)
            .flatMap(maxPublishers: .max(maxConcurrentRequests)) { task -> AnyPublisher<(NIP05Task, Data?), Never> in
                URLSession.shared.dataTaskPublisher(for: task.nip05url!)
                    .map { (task, $0.data) }
                    .replaceError(with: (task, nil))
                    .eraseToAnyPublisher()
            }
            .filter { (task, data) in data != nil }
            .sink { [weak self] (task, data) in
                bg().perform { [weak self] in
                    guard let self else { return }
                    if let nostrJson = try? self.decoder.decode(NostrJson.self, from: data!) {
                        if let pubkey = nostrJson.names[task.name] {
                            if pubkey != "" && pubkey == task.contact.pubkey {
                                task.contact.nip05verifiedAt = Date.now
                                ViewUpdates.shared.nip05updated.send((pubkey, true, task.contact.nip05 ?? "", task.name))
#if DEBUG
                                L.fetching.debug("verifySubject: 👍 nip05 verified \(task.contact.nip05 ?? "")")
#endif
                            }
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    /// Namecoin (.bit) verification sidecar. Resolves via ElectrumX and, if
    /// the resolved pubkey matches, marks nip05verifiedAt on the Contact.
    /// Captures only value types into the Task to stay Sendable-clean.
    private func verifyNamecoin(contact: Contact, nip05: String) {
        let pubkey = contact.pubkey
        Task.detached {
            guard let result = await NamecoinService.shared.resolve(nip05) else { return }
            guard result.pubkey == pubkey else {
                #if DEBUG
                print("[Namecoin] nip05 \(nip05) resolved to \(result.pubkey.prefix(8))… but contact pubkey is \(pubkey.prefix(8))…")
                #endif
                return
            }
            await Self.persistNamecoinVerified(pubkey: pubkey, nip05: nip05)
        }
    }

    private static func persistNamecoinVerified(pubkey: String, nip05: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let ctx = bg()
            ctx.perform {
                if let bgContact = Contact.fetchByPubkey(pubkey, context: ctx) {
                    bgContact.nip05verifiedAt = Date.now
                    ViewUpdates.shared.nip05updated.send((pubkey, true, nip05, "_"))
                    #if DEBUG
                    L.fetching.debug("verifySubject: 👍 namecoin nip05 verified \(nip05)")
                    #endif
                }
                cont.resume()
            }
        }
    }

    public func verify(_ contact: Contact) {
#if DEBUG
        if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            fatalError("Should only be called from bg()")
        }
        
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
#endif

#if DEBUG
        L.fetching.debug("nip05: going to verify \(contact.nip05 ?? "") for \(contact.pubkey)")
#endif
        self.verifySubject.send(contact)
    }
    
    static func shouldVerify(_ contact: Contact) -> Bool {
#if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return false
        }
        if Thread.isMainThread {
            fatalError("Should call from bg")
        }
#endif
        guard contact.nip05 != nil else { return false }
        return (contact.nip05verifiedAt == nil || (contact.nip05verifiedAt != nil) && (contact.nip05verifiedAt! < Self.fourWeeksAgo))
    }
}

struct NIP05Task {
    var contact: Contact
    let nip05url: URL?
    let domain: String
    let name: String
    var nostrJson: NostrJson? = nil
}


struct NostrJson: Codable {
    var names: [String:String]
}


func nip05nameOnly(nip05veried: Bool, nip05: String? = nil) -> String {
    guard nip05veried else { return "..." }
    guard let parts = nip05?.split(separator: "@"), parts.count >= 2 else { return "" }
    guard let name = parts[safe: 0] else { return "" }
    guard !name.isEmpty else { return "" }
    return String(name)
}
