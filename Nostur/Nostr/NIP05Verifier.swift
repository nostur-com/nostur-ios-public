//
//  NIP05VerificationPipeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/05/2023.
//

import Foundation
import Combine

// Buffer up to 50 pending verifications, check as fast as possible
// while not doing more than 2 simultaniously
// Caches failed request so we don't keep retrying
class NIP05Verifier {
    static let shared = NIP05Verifier()
    private let maxConcurrentRequests:Int = 2
    private let bufferSize:Int = 50
    private var verifySubject = PassthroughSubject<Contact, Never>()
    
    private var cancellables = Set<AnyCancellable>()
    
    public static var fourWeeksAgo = Date.now.addingTimeInterval(-(28 * 86400))
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
            .filter { contact in
                let nip05trimmed = contact.nip05!.trimmingCharacters(in: .whitespacesAndNewlines)
                let nip05parts = nip05trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
                return nip05parts.count == 2 && FailedURLCache.shared.retrieveObject(at: String(nip05parts[1])) == nil
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
            .sink { (task, data) in
                DataProvider.shared().bg.perform {
                    if let nostrJson = try? self.decoder.decode(NostrJson.self, from: data!) {
                        if let pubkey = nostrJson.names[task.name] {
                            if pubkey != "" && pubkey == task.contact.pubkey {
                                task.contact.objectWillChange.send()
                                task.contact.nip05verifiedAt = Date.now
                                task.contact.nip05updated.send(true)
                                L.fetching.info("👍 nip05 verified \(task.contact.nip05 ?? "")")
                            }
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    public func verify(_ contact: Contact) {
#if DEBUG
if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
    return
}
#endif
        if contact.managedObjectContext == DataProvider.shared().bg {
            self.verifySubject.send(contact)
        }
        
        DataProvider.shared().bg.perform { [unowned self] in
            if let privateContact = DataProvider.shared().bg.object(with: contact.objectID) as? Contact {
                L.fetching.info("  nip05: going to verify \(privateContact.nip05 ?? "") for \(privateContact.pubkey)")
                self.verifySubject.send(privateContact)
            }
        }
    }
    
    static func shouldVerify(_ contact: Contact) -> Bool {
        guard contact.nip05 != nil else { return false }
        return (contact.nip05verifiedAt == nil || (contact.nip05verifiedAt != nil) && (contact.nip05verifiedAt! < Self.fourWeeksAgo))
    }
}

struct NIP05Task {
    var contact:Contact
    let nip05url:URL?
    let domain:String
    let name:String
    var nostrJson:NostrJson? = nil
}


struct NostrJson : Codable {
    var names: [String:String]
}
