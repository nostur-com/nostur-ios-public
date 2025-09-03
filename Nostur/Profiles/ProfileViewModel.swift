//
//  ProfileViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2025.
//

import SwiftUI
import NostrEssentials
import CoreData
import Combine

class ProfileViewModel: ObservableObject {
    @Published var isFollowingYou = false
    @Published var showHighlightsTab = false
    @Published var showArticlesTab = false
    @Published var showListsTab = false
    @Published var fixedPfp: URL?
    @Published var npub = ""
    
    @Published var newPostsNotificationsEnabled: Bool = false
    @Published var pinnedPost: NRPost?
    
    private let backlog = Backlog(timeout: 4.0, auto: true, backlogDebugName: "ProfileViewModel")
    private var pubkey: String?
    
    private var subscriptions: Set<AnyCancellable> = []
    
    public init() {}
    
    public func load(_ nrContact: NRContact) {
        let pubkey = nrContact.pubkey
        self.pubkey = pubkey
        Task { @MainActor in
            newPostsNotificationsEnabled = NewPostNotifier.shared.isEnabled(for: nrContact.pubkey)
        }
        Task.detached {
            // Load npub
            let npub = try! NIP19(prefix: "npub", hexString: pubkey).displayString
            Task { @MainActor [weak self] in
                self?.npub = npub
            }
        }
        self.loadOldPFP(nrContact)
        self.loadArticles(nrContact)
        Task.detached {
            await self.loadPinned(nrContact)
        }
        Task.detached {
            await self.loadHighlights(nrContact)
        }
        self.loadLists(nrContact)
        
        bg().perform { [weak self] in
            guard let contact: Contact = Contact.fetchByPubkey(pubkey, context: bg()) else { return }
            
            self?.loadProfileKinds(contact)
            
            if NIP05Verifier.shouldVerify(contact) {
                NIP05Verifier.shared.verify(contact)
            }
            
            self?.loadLuds(nrContact: nrContact)
            EventRelationsQueue.shared.addAwaitingContact(contact, debugInfo: "ProfileViewModel")
            
            // "Follows you"
            if contact.followsYou() {
                Task { @MainActor [weak self] in
                    self?.isFollowingYou = true
                }
            }
        }
        
        listenForDeletedPosts()
        listenForDidPin()
    }
    
    private func listenForDidPin() {
        receiveNotification(.didPinPost)
            .map { notification in
                return (notification.object as! PinPostInfo)
            }
            .filter { $0.pinEvent.publicKey == self.pubkey }
            .receive(on: RunLoop.main)
            .sink { [weak self] pinPostInfo in
                guard let self = self else { return }
                Task { @MainActor in
                    withAnimation {
                        self.pinEventId = pinPostInfo.pinEvent.id
                        self.pinnedPost = pinPostInfo.pinnedPost
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    private func listenForDeletedPosts() {
        ViewUpdates.shared.postDeleted
            .receive(on: RunLoop.main)
            .sink { [weak self] deletion in
                guard let self = self else { return }
                if let pinEventId = self.pinEventId, deletion.toDeleteId == pinEventId {
                    withAnimation {
                        self.pinnedPost = nil
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    @MainActor
    public func toggleNewPostNotifications(_ pubkey: String) {
        newPostsNotificationsEnabled = !NewPostNotifier.shared.isEnabled(for: pubkey)
        NewPostNotifier.shared.toggle(pubkey)
    }
    
    @MainActor
    public func copyProfileSource(_ nrContact: NRContact) {
        bg().perform {
            let kind0 = Event.fetchRequest()
            kind0.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
            kind0.predicate = NSPredicate(format: "pubkey == %@ AND kind == 0", nrContact.pubkey)
            
            if let event = try? bg().fetch(kind0).first {
                let json = event.toNEvent().eventJson()
                DispatchQueue.main.async {
                    UIPasteboard.general.string = json
                }
            }
        }
    }
    
    public func loadProfileKinds(_ contact: Contact) {
        let task = ReqTask(
            reqCommand: { (taskId) in
                let filters = [Filters(authors: [contact.pubkey], kinds: [0,3,30008,10002,10063], limit: 25)]
                outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: taskId, filters: filters))
            },
            processResponseCommand: { (taskId, _, _) in
                bg().perform {
                    if (contact.followsYou()) {
                        Task { @MainActor [weak self] in
                            self?.isFollowingYou = true
                        }
                    }
                }
            },
            timeoutCommand: { taskId in
                bg().perform {
                    if (contact.followsYou()) {
                        Task { @MainActor [weak self] in
                            self?.isFollowingYou = true
                        }
                    }
                }
            })
        
        backlog.add(task)
        task.fetch()
    }
    
    private func loadLuds(nrContact: NRContact) {
        guard nrContact.anyLud else { return }
        let lud16orNil = nrContact.lud16
        let lud06orNil = nrContact.lud06
        Task {
            do {
                if let lud16 = lud16orNil, lud16 != "" {
                    let response = try await LUD16.getCallbackUrl(lud16: lud16)
                    if (response.allowsNostr ?? false), let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
                        await bg().perform {
                            nrContact.zapperPubkeys.insert(zapperPubkey)
#if DEBUG
                            L.og.info("⚡️ contact.zapperPubkey updated: \(zapperPubkey)")
#endif
                        }
                    }
                }
                else if let lud06 = lud06orNil, lud06 != "" {
                    let response = try await LUD16.getCallbackUrl(lud06: lud06)
                    if (response.allowsNostr ?? false), let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
                        await bg().perform {
                            nrContact.zapperPubkeys.insert(zapperPubkey)
#if DEBUG
                            L.og.info("⚡️ contact.zapperPubkey updated: \(zapperPubkey)")
#endif
                        }
                    }
                }
            }
            catch {
#if DEBUG
                L.og.error("⚡️🔴 problem in lnurlp \(error)")
#endif
            }
        }
    }
    
    private func loadOldPFP(_ nrContact: NRContact) {
        guard !SettingsStore.shared.lowDataMode else { return }
        guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
        
        bg().perform { [weak self] in
            guard let self else { return }
            if let fixedPfpURL = nrContact.fixedPfpURL,
               fixedPfpURL != nrContact.pictureUrl,
               hasFPFcacheFor(pfpImageRequestFor(fixedPfpURL))
            {
                Task { @MainActor [weak self] in
                    withAnimation {
                        self?.fixedPfp = fixedPfpURL
                    }
                }
            }
        }
    }
    
    // Not the pinned post, but the event pinning the post
    // Need to keep to remove pinned post on unpin from view
    private var pinEventId: String?
    
    public func loadPinned(_ nrContact: NRContact) async {
        let pubkey = nrContact.pubkey
        _ = try? await relayReq(Filters(authors: [pubkey], kinds: [10601]), timeout: 5.5)
        
        let pinnedPost: NRPost? = await withBgContext { bgContext in
            let event = Event.fetchReplacableEvent(10601, pubkey: pubkey, context: bgContext)
            if let firstE = event?.firstE(),
               let pinnedEvent = Event.fetchEvent(id: firstE, context: bgContext),
               pinnedEvent.pubkey == pubkey
            {
                let pinEventId = event?.id
                Task { @MainActor in
                    self.pinEventId = pinEventId
                }
                return NRPost(event: pinnedEvent)
            }
            return nil
        }
        
        guard let pinnedPost else { return }
        Task { @MainActor [weak self] in
            withAnimation {
                self?.pinnedPost = pinnedPost
            }
        }
    }
    
    public func loadHighlights(_ nrContact: NRContact) async {
        let pubkey = nrContact.pubkey
        
        let postIds: [String] = await withBgContext { _ in
            Event.fetchReplacableEvent(10001, pubkey: pubkey)?.fastEs.map { $0.1 } ?? []
        }
        
        if !postIds.isEmpty {
            Task { @MainActor [weak self] in
                self?.showHighlightsTab = true
            }
            return
        }
        
        _ = try? await relayReq(Filters(authors: [pubkey], kinds: [10001]), timeout: 4.5)
        
        let postIdsAfter: [String] = await withBgContext { _ in
            Event.fetchReplacableEvent(10001, pubkey: pubkey)?.fastEs.map { $0.1 } ?? []
        }
        
        if !postIdsAfter.isEmpty {
            Task { @MainActor [weak self] in
                self?.showHighlightsTab = true
            }
            return
        }
    }
    
    public func loadArticles(_ nrContact: NRContact) {
        let reqTask = ReqTask(prefix: "HASART-", reqCommand: { taskId in
            let filters = [Filters(authors: [nrContact.pubkey], kinds: [30023], limit: 50)]
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: taskId, filters: filters))
        }, processResponseCommand: { taskId, _, _ in
            bg().perform {
                if Event.fetchMostRecentEventBy(pubkey: nrContact.pubkey, andKind: 30023, context: bg()) != nil {
                    Task { @MainActor [weak self] in
                        withAnimation {
                            self?.showArticlesTab = true
                        }
                    }
                }
            }
        }, timeoutCommand: { taskId in
            bg().perform {
                if Event.fetchMostRecentEventBy(pubkey: nrContact.pubkey, andKind: 30023, context: bg()) != nil {
                    Task { @MainActor [weak self] in
                        withAnimation {
                            self?.showArticlesTab = true
                        }
                    }
                }
            }
        })
        
        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    public func loadLists(_ nrContact: NRContact) {
        let reqTask = ReqTask(prefix: "HASLIST-", reqCommand: { taskId in
            let filters = [Filters(authors: [nrContact.pubkey], kinds: [30000,39089], limit: 25)]
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: taskId, filters: filters))
        }, processResponseCommand: { taskId, _, _ in
            bg().perform { [weak self] in
                self?.fetchFromDb(pubkey: nrContact.pubkey)
            }
        }, timeoutCommand: { taskId in
            bg().perform { [weak self] in
                self?.fetchFromDb(pubkey: nrContact.pubkey)
            }
        })
        
        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    
    private func fetchFromDb(pubkey: String) {
        // Follow sets with some garbage filtering
        let garbage: Set<String> = ["mute", "allowlist", "mutelists"]
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = NSPredicate(format: "kind = 30000 AND pubkey == %@ AND mostRecentId == nil AND content == \"\" AND NOT dTag IN %@",
        pubkey, garbage)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        request.fetchLimit = 30
        let followSets = (try? bg().fetch(request)) ?? []
        
        // Only lists with between 2 and 500 pubkeys
        let followSetsWithLessGarbage = followSets.filter { list in
            list.fastPs.count > 2 && list.fastPs.count <= 500 && noGarbageDtag(list.dTag)
        }
        
        // Follow packs, no garbage filtering needed
        let request2 = NSFetchRequest<Event>(entityName: "Event")
        request2.predicate = NSPredicate(format: "kind = 39089 AND pubkey == %@ AND mostRecentId == nil", pubkey)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        request.fetchLimit = 30
        let followPacks = ((try? bg().fetch(request2)) ?? [])
            .filter { !$0.fastPs.isEmpty }

        if followSetsWithLessGarbage.count > 0 || !followPacks.isEmpty {
            Task { @MainActor [weak self] in
                withAnimation {
                    self?.showListsTab = true
                }
            }
        }
    }
    
}
