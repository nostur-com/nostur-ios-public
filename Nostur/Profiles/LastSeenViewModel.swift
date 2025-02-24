//
//  LastSeenViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2025.
//

import SwiftUI
import NostrEssentials

class LastSeenViewModel: ObservableObject {
    @Published var lastSeen: String? = nil
    
    private let backlog = Backlog(timeout: 4.0, auto: true)
    
    @MainActor
    public func checkLastSeen(_ pubkey: String) {
        let reqTask = ReqTask(prefix: "SEEN-", reqCommand: { taskId in
            let filters = [Filters(authors: [pubkey], limit: 1)]
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: taskId, filters: filters))
        }, processResponseCommand: { taskId, _, _ in
            bg().perform {
                if let last = Event.fetchLastSeen(pubkey: pubkey, context: bg()) {
                    let agoString = last.date.agoString
                    Task { @MainActor [weak self] in
                        self?.lastSeen = String(localized: "Last seen: \(agoString) ago", comment:"Label on profile showing when last seen, example: Last seen: 10m ago")
                    }
                }
            }
        }, timeoutCommand: { taskId in
            bg().perform {
                if let last = Event.fetchLastSeen(pubkey: pubkey, context: bg()) {
                    let agoString = last.date.agoString
                    Task { @MainActor [weak self] in
                        self?.lastSeen = String(localized: "Last seen: \(agoString) ago", comment:"Label on profile showing when last seen, example: Last seen: 10m ago")
                    }
                }
            }
        })
        backlog.add(reqTask)
        reqTask.fetch()
    }
}
