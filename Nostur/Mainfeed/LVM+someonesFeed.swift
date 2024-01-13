//
//  LVM+someonesFeed.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/09/2023.
//

import Foundation

extension LVM {
    
    @MainActor public func loadSomeonesFeed(_ someonesPubkey: String) {
        sTab = "Main"
        ssTab = "Following"
        
        instantFeed.backlog.clear()
        backlog.clear()
        
        hashtags = []
        lvmCounter.count = 0
        L.og.debug("COUNTER: \(self.lvmCounter.count) - LVM.loadSomeonesFeed()")
        posts.send([:])
        instantFinished = false
        bg().perform { [weak self] in
            self?.pubkeys = []
            self?.nrPostLeafs = []
            if !SettingsStore.shared.appWideSeenTracker {
                self?.onScreenSeen = []
            }
            self?.leafIdsOnScreen = []
            self?.leafsAndParentIdsOnScreen = []
        }
        fetchSomeoneElsesContacts(someonesPubkey)
    }
    
    func fetchSomeoneElsesContacts(_ pubkey: String) {   
        let getContactListTask = ReqTask(
            prio: true,
            reqCommand: { taskId in
                L.og.notice("🟪 Fetching clEvent from relays")
                reqP(RM.getAuthorContactsList(pubkey: pubkey, subscriptionId: taskId))
            },
            processResponseCommand: { taskId, _, clEvent in
                bg().perform { [weak self] in
                    guard let self = self else { return }
                    L.og.notice("🟪 Processing clEvent response from relays")
                    if let clEvent = clEvent {
                        self.pubkeys = Set(clEvent.fastPs.map { $0.1 })
                        
                        let hashtags = clEvent.fastTs.map { $0.1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                        self.hashtags = Set(hashtags)
                        
                        self.fetchSomeoneElsesFeed()
                    }
                    else if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                        self.pubkeys = Set(clEvent.fastPs.map { $0.1 })
                        
                        let hashtags = clEvent.fastTs.map { $0.1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                        self.hashtags = Set(hashtags)
                        
                        self.fetchSomeoneElsesFeed()
                    }
                }
            },
            timeoutCommand: { [weak self] taskId in
                guard let self = self else { return }
                if (self.pubkeys.isEmpty) {
                    L.og.notice("🟪  \(taskId) Timeout in fetching clEvent / pubkeys")
                    bg().perform { [weak self] in
                        if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                            self?.pubkeys = Set(clEvent.fastPs.map { $0.1 })
                            
                            let hashtags = clEvent.fastTs.map { $0.1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                            self?.hashtags = Set(hashtags)
                            
                            self?.fetchSomeoneElsesFeed()
                        }
                    }
                }
            }
        )
        self.backlog.add(getContactListTask)
        getContactListTask.fetch()
    }
    
    func fetchSomeoneElsesFeed() {
        let getFollowingEventsTask = ReqTask(
            prefix: "GFETOTHER-",
            reqCommand: { taskId in
                L.og.notice("🟪 Fetching posts from relays using \(self.pubkeys.count) pubkeys")
                reqP(RM.getFollowingEvents(pubkeys: Array(self.pubkeys), limit: 400, subscriptionId: taskId))
            },
            processResponseCommand: { taskId, _, _  in
                bg().perform { [weak self] in
                    guard let self = self else { return }
                    let fr = Event.postsByPubkeys(pubkeys, lastAppearedCreatedAt: 0)
                    guard let events = try? bg().fetch(fr) else {
                        L.og.notice("🟪 \(taskId) Could not fetch posts from relays using \(pubkeys.count) pubkeys. Our pubkey: \(self.pubkey?.short ?? "-") ")
                        return
                    }
                    guard events.count > 20 else {
                        L.og.notice("🟪 \(taskId) Received only \(events.count) events, waiting for more. Our pubkey: \(self.pubkey?.short ?? "-") ")
                        return
                    }
                    DispatchQueue.main.async {
                        self.loadSomeoneElsesEvents(events)
                    }
                    L.og.notice("🟪 Received \(events.count) posts from relays (found in db)")
                }
            },
            timeoutCommand: { taskId in
            
            }
        )
        self.backlog.add(getFollowingEventsTask)
        getFollowingEventsTask.fetch()
    }
    
    func loadSomeoneElsesEvents(_ events:[Event]) {
        self.startRenderingSubject.send(events)
        
        if (!self.instantFinished) {
            self.performLocalFetchAfterImport()
        }
        self.instantFinished = true
        
        DispatchQueue.main.async {
            self.fetchRealtimeSinceNow(subscriptionId: self.id) // Subscription should stay active
        }
        
        let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 4)  // 4 hours  ago

        // Continue from first (newest) on screen?
        let since = (self.nrPostLeafs.first?.created_at ?? hoursAgo) - (60 * 5) // (take 5 minutes earlier to not mis out of sync posts)
        let ago = Date(timeIntervalSince1970: Double(since)).agoString

        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [weak self] in
            guard let self = self else { return }
            self.fetchNewerSince(subscriptionId: "\(self.id)-\(ago)", since:NTimestamp(timestamp: Int(since))) // This one closes after EOSE
            fetchProfiles(pubkeys: self.pubkeys, subscriptionId: "SomeoneElsesProfiles")
        }
    }
    
    @MainActor public func revertBackToOwnFeed() {
        guard let account = account() else { return }
        sTab = "Main"
        ssTab = "Following"
        
        instantFeed.backlog.clear()
        backlog.clear()
        
        self.pubkey = account.publicKey
        let pubkeys = account.getFollowingPublicKeys(includeBlocked: false)
        self.loadHashtags()
        lvmCounter.count = 0
        L.og.debug("COUNTER: \(self.lvmCounter.count) - LVM.revertBackToOwnFeed()")
        instantFinished = false
        posts.send([:])
        bg().perform { [weak self] in
            self?.pubkeys = pubkeys
            self?.nrPostLeafs = []
            if !SettingsStore.shared.appWideSeenTracker {
                self?.onScreenSeen = []
            }
            self?.leafIdsOnScreen = []
            self?.leafsAndParentIdsOnScreen = []
        }
        startInstantFeed()
    }
}
