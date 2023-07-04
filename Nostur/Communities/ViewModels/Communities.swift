//
//  Communities.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/07/2023.
//

import SwiftUI

class Communities: ObservableObject {
    @AppStorage("communities_most_recent_created_at") var mostRecentCreatedAt:Int = 0
    @Published var communities:[Community] = []
    
    private var backlog = Backlog(timeout: 10.0, auto: true)
    private var bg = DataProvider.shared().bg
    
    public func fetchCommunities() {
        let reqTask = ReqTask(
            debounceTime: 1.0,
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
                            Community(id: $0.aTag, title: $0.communityName, image: $0.communityImage, moderators: [])
                        }
                    
                    if let mostRecent = events.max(by: { $0.created_at > $1.created_at }) {
                        DispatchQueue.main.async {
                            self.communities = communities
                            self.mostRecentCreatedAt = Int(mostRecent.created_at)
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
                                Community(id: $0.aTag, title: $0.communityName, image: $0.communityImage, moderators: [])
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
}
