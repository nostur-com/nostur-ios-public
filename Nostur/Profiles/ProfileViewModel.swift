//
//  ProfileViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2025.
//

import SwiftUI
import NostrEssentials
import CoreData

class ProfileViewModel: ObservableObject {
    @Published var isFollowingYou = false
    @Published var showArticlesTab = false
    @Published var showListsTab = false
    @Published var fixedPfp: URL?
    @Published var npub = ""
    
    @Published var newPostsNotificationsEnabled: Bool = false
    
    private let backlog = Backlog(timeout: 4.0, auto: true)
    private var pubkey: String?
    
    public init() {}
    
    public func load(_ nrContact: NRContact) {
        let pubkey = nrContact.pubkey
        self.pubkey = pubkey
        Task { @MainActor in
            newPostsNotificationsEnabled = NewPostNotifier.shared.isEnabled(for: nrContact.pubkey)
        }
        self.loadOldPFP(nrContact)
        self.loadProfileKinds(nrContact)
        self.loadArticles(nrContact)
        self.loadLists(nrContact)
        
        bg().perform { [weak self] in
            
            if let contact = nrContact.contact, NIP05Verifier.shouldVerify(contact) {
                NIP05Verifier.shared.verify(contact)
            }
            
            // Load npub
            let npub = try! NIP19(prefix: "npub", hexString: pubkey).displayString
            Task { @MainActor [weak self] in
                self?.npub = npub
            }
            
            self?.loadLuds(nrContact)
            
            guard let contact = nrContact.contact else { return }
            EventRelationsQueue.shared.addAwaitingContact(contact, debugInfo: "ProfileViewModel")
            
            // "Follows you"
            if contact.followsYou() {
                Task { @MainActor [weak self] in
                    self?.isFollowingYou = true
                }
            }
        }
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
    
    public func loadProfileKinds(_ nrContact: NRContact) {
        let task = ReqTask(
            reqCommand: { (taskId) in
                let filters = [Filters(authors: [nrContact.pubkey], kinds: [0,3,30008,10002], limit: 20)]
                outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: taskId, filters: filters))
            },
            processResponseCommand: { (taskId, _, _) in
                bg().perform {
                    if (nrContact.contact?.followsYou() ?? false) {
                        Task { @MainActor [weak self] in
                            self?.isFollowingYou = true
                        }
                    }
                }
            },
            timeoutCommand: { taskId in
                bg().perform {
                    if (nrContact.contact?.followsYou() ?? false) {
                        Task { @MainActor [weak self] in
                            self?.isFollowingYou = true
                        }
                    }
                }
            })
        
        backlog.add(task)
        task.fetch()
    }
    
    private func loadLuds(_ nrContact: NRContact) {
        guard let contact = nrContact.contact else { return }
        guard contact.anyLud else { return }
        let lud16orNil = contact.lud16
        let lud06orNil = contact.lud06
        Task { [weak contact] in
            do {
                if let lud16 = lud16orNil, lud16 != "" {
                    let response = try await LUD16.getCallbackUrl(lud16: lud16)
                    if (response.allowsNostr ?? false), let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
                        await bg().perform {
                            guard let contact else { return }
                            contact.zapperPubkeys.insert(zapperPubkey)
                            L.og.info("⚡️ contact.zapperPubkey updated: \(zapperPubkey)")
                        }
                    }
                }
                else if let lud06 = lud06orNil, lud06 != "" {
                    let response = try await LUD16.getCallbackUrl(lud06: lud06)
                    if (response.allowsNostr ?? false), let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
                        await bg().perform {
                            guard let contact else { return }
                            contact.zapperPubkeys.insert(zapperPubkey)
                            L.og.info("⚡️ contact.zapperPubkey updated: \(zapperPubkey)")
                        }
                    }
                }
            }
            catch {
                L.og.error("⚡️🔴 problem in lnurlp \(error)")
            }
        }
    }
    
    private func loadOldPFP(_ nrContact: NRContact) {
        guard !SettingsStore.shared.lowDataMode else { return }
        guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
        
        bg().perform { [weak self] in
            guard let self else { return }
            if let fixedPfp = nrContact.contact?.fixedPfp,
               fixedPfp != nrContact.contact?.picture,
               let fixedPfpUrl = URL(string: fixedPfp),
               hasFPFcacheFor(pfpImageRequestFor(fixedPfpUrl))
            {
                Task { @MainActor [weak self] in
                    withAnimation {
                        self?.fixedPfp = fixedPfpUrl
                    }
                }
            }
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
            bg().perform {
                let garbage: Set<String> = ["mute", "allowlist", "mutelists"]
                let request = NSFetchRequest<Event>(entityName: "Event")
                request.predicate = NSPredicate(format: "kind IN {30000,39089} AND pubkey == %@ AND mostRecentId == nil AND content == \"\" AND NOT dTag IN %@", nrContact.pubkey, garbage)
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                request.fetchLimit = 30
                let lists = (try? bg().fetch(request)) ?? []
                
                // Only lists with between 2 and 500 pubkeys
                let listsWithLessGarbage = lists.filter { list in
                    list.fastPs.count > 2 && list.fastPs.count <= 500 && noGarbageDtag(list.dTag)
                }
                
                if listsWithLessGarbage.count > 0 {
                    Task { @MainActor [weak self] in
                        withAnimation {
                            self?.showListsTab = true
                        }
                    }
                }
            }
        }, timeoutCommand: { taskId in
            bg().perform {
                let garbage: Set<String> = ["mute", "allowlist", "mutelists"]
                let request = NSFetchRequest<Event>(entityName: "Event")
                request.predicate = NSPredicate(format: "kind IN {30000,39089} AND pubkey == %@ AND mostRecentId == nil AND content == \"\" AND NOT dTag IN %@", nrContact.pubkey, garbage)
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                request.fetchLimit = 30
                let lists = (try? bg().fetch(request)) ?? []
                
                // Only lists with between 2 and 500 pubkeys
                let listsWithLessGarbage = lists.filter { list in
                    list.fastPs.count > 2 && list.fastPs.count <= 500 && noGarbageDtag(list.dTag)
                }
                
                if listsWithLessGarbage.count > 0 {
                    Task { @MainActor [weak self] in
                        withAnimation {
                            self?.showListsTab = true
                        }
                    }
                }
            }
        })
        
        backlog.add(reqTask)
        reqTask.fetch()
    }
    
}
