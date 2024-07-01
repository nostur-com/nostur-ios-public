//
//  OutboxLoader.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/07/2024.
//

import Foundation
import CoreData
import NostrEssentials

public class OutboxLoader {
    
    private let pubkey: String // Account
    private let follows: Set<String> // Follows
    private let context: NSManagedObjectContext

    private var mostRecentKind10002At: Int?
    
    private var cp: ConnectionPool
    private var backlog: Backlog
    
    init(pubkey: String, follows: Set<String> = [], cp: ConnectionPool) {
        self.pubkey = pubkey
        self.follows = follows
        self.cp = cp
        self.backlog = Backlog(timeout: 60, auto: true)
        self.context = bg()
        
        self.load()
    }

    public func load() {
        
        // Load from DB, then fetch more
        
        self.loadKind10002sFromDb { kind10002s in
            
            self.mostRecentKind10002At = kind10002s.sorted(by: { $0.created_at > $1.created_at }).first?.created_at
            self.cp.setPreferredRelays(using: kind10002s)
            
            L.sockets.debug("📤📤 Outbox: loaded \(kind10002s.count) from db")
            self.fetchMoreKind10002sFromRelays()
        }
    }
    
    private func loadKind10002sFromDb(_ completion: (([NostrEssentials.Event]) -> Void)? = nil) {
        context.perform { [weak self] in
            guard let self else { return }
            
            let kind10002s: [NostrEssentials.Event] = Event.fetchReplacableEvents(10002, pubkeys: self.follows, context: context)
                .map { event in
                    return event.toNostrEssentialsEvent()
                }
            completion?(kind10002s)
        }
    }
    
    private func fetchMoreKind10002sFromRelays() {
        let task = ReqTask(
            debounceTime: 3.0,
            prefix: "OUTBOX1-",
            reqCommand: { [weak self] taskId in
                guard let self, let cm = NostrEssentials
                    .ClientMessage(type: .REQ,
                                   subscriptionId: taskId,
                                   filters: [Filters(authors: self.follows, kinds: [10002], since: self.mostRecentKind10002At)]
                    ).json()
                else { return }
                
                L.sockets.debug("📤📤 Outbox: Fetching contact relay info for \(self.follows) follows")
                req(cm)
            },
            processResponseCommand: { [weak self] taskId, _, _ in
                guard let self else { return }
                
                self.loadKind10002sFromDb { kind10002s in
                    
                    self.mostRecentKind10002At = kind10002s.sorted(by: { $0.created_at > $1.created_at }).first?.created_at
                    self.cp.setPreferredRelays(using: kind10002s)
                    
                    L.sockets.debug("📤📤 Outbox: loaded \(kind10002s.count) from db")
                }
            },
            timeoutCommand: { taskId in
                L.sockets.debug("📤📤 Outbox: timeout or no new kind 10002s")
            })

        backlog.add(task)
        task.fetch()
    }
}


extension Event {
    func toNostrEssentialsEvent() -> NostrEssentials.Event {
        return NostrEssentials.Event(
            pubkey: self.pubkey,
            content: self.content ?? "",
            kind: Int(self.kind),
            created_at: Int(self.created_at),
            id: self.id,
            tags: tagsSerializedToTags(self.tagsSerialized),
            sig: self.sig ?? "")
    }
}

// From Nostur .tagsSerialized to [NostrEssentials.Tag]
func tagsSerializedToTags(_ tagsSerialized: String?) -> [Tag] {
    guard let tagsSerialized = tagsSerialized else { return [] }
    guard let jsonData = tagsSerialized.data(using: .utf8) else { return [] }
    
    guard let jsonArray = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String]] else {
        return []
    }
    
    return jsonArray.map { stringArray in
        return Tag(stringArray)
    }
}
