//
//  Communities.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/07/2023.
//
//

import SwiftUI

class Communities: ObservableObject {
    @AppStorage("communities_most_recent_created_at") var mostRecentCreatedAt:Int = 0
    @Published var communities:[Community] = []
    @Published var newCommunities:[Community] = []
    @Published var showNewCommunities = false
    
    private var backlog = Backlog(timeout: 0.2, auto: true)
    private var bg = DataProvider.shared().bg
    
    public func fetchCommunities() {
        let reqTask = ReqTask(
            debounceTime: 5.0,
            prefix: "FC-",
            reqCommand: { [weak self] taskId in
                guard let self = self else { return }
                req(RM.getCommunities(subscriptionId: taskId, since: NTimestamp(timestamp: self.mostRecentCreatedAt)))
            },
            processResponseCommand: { [weak self] taskId, _ in
                guard let self = self else { return }
                self.bg.perform { [weak self] in
                    guard let self = self else { return }
                    let events = Event.fetchCommunities(context: self.bg)
                    let communities = events
                        .map {
                            Community(event: $0)
                        }
                        .sorted {
                            ($0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending)
                        }
                    
                    if let mostRecent = events.max(by: { $0.created_at > $1.created_at }) {
                        let mostRecentCreatedAt = Int(mostRecent.created_at)
                        DispatchQueue.main.async {
                            if self.communities.isEmpty {
                                self.communities = communities
                            }
                            else {
                                self.newCommunities = communities
                            }
                            self.mostRecentCreatedAt = mostRecentCreatedAt
                        }
                    }
                }
            },
            timeoutCommand: { [weak self] taskId in
                guard let self = self else { return }
                if communities.isEmpty {
                    self.bg.perform { [weak self] in
                        guard let self = self else { return }
                        let events = Event.fetchCommunities(context: self.bg)
                        let communities = events
                            .map {
                                Community(event: $0)
                            }
                            .sorted {
                                ($0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending)
                            }
                        
                        DispatchQueue.main.async {
                            self.communities = communities
                        }
                    }
                }
            })
        
        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    public func loadCommunities() {
        bg.perform { [weak self] in
            guard let self = self else { return }
            let events = Event.fetchCommunities(context: self.bg)
            let communities = events
                .map {
                    Community(event: $0)
                }
                .sorted {
                    ($0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending)
                }
            
            if let mostRecent = events.max(by: { $0.created_at > $1.created_at }) {
                let mostRecentCreatedAt = Int(mostRecent.created_at)
                DispatchQueue.main.async {
                    self.communities = communities
                    self.mostRecentCreatedAt = mostRecentCreatedAt
                }
            }
        }
    }
}
