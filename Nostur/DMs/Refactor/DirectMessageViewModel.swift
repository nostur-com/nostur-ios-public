//
//  DirectMessageViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/09/2023.
//

import Foundation
import NostrEssentials
import Combine

class DirectMessageViewModel: ObservableObject {
    
    static public let `default` = DirectMessageViewModel()
    
    var pubkey:String?
    var lastNotificationReceivedAt:Date? = nil
    
    @Published var conversationRows:[Conversation] = []
    @Published var requestRows:[Conversation] = []
    @Published var requestRowsNotWoT:[Conversation] = []
    
    @Published var showNotWoT = false {
        didSet {
            if showNotWoT {
                requestRows = requestRows + requestRowsNotWoT
            }
            else {
                self.reloadMessageRequests()
            }
        }
    }
     
    var unread:Int {
        conversationRows.reduce(0) { $0 + $1.unread }
    }
    var newRequests:Int {
        requestRows.reduce(0) { $0 + $1.unread }
    }
    
    var newRequestsNotWoT:Int {
        requestRowsNotWoT.count
    }
    
    private var subscriptions = Set<AnyCancellable>()
    
    private init() {
        bg().perform {
            self._reloadAccepted
                .debounce(for: 1.0, scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.loadAcceptedConversations()
                }
                .store(in: &self.subscriptions)
            
            self._reloadMessageRequests
                .debounce(for: 0.5, scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.loadMessageRequests()
                }
                .store(in: &self.subscriptions)
            
            self._reloadMessageRequestsNotWot
                .debounce(for: 0.5, scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.loadOutSideWoT()
                }
                .store(in: &self.subscriptions)
            
            receiveNotification(.blockListUpdated)
                .sink { [weak self] _ in
                    guard let self else { return }
                    showNotWoT = false
                    self.reloadAccepted()
                    self.reloadMessageRequests()
                    self.reloadMessageRequestsNotWot()
                }
                .store(in: &self.subscriptions)
        }
    }
    
    // .load is called from:
    // NosturState on startup if WoT is disabled
    // receiveNotification(.WoTReady) if WoT is enabled, after WoT has loaded
    public func load(pubkey: String) {
        conversationRows = []
        requestRows = []
        requestRowsNotWoT = []
        self.pubkey = pubkey
        self.loadAcceptedConversations()
        self.loadMessageRequests()
        self.loadOutSideWoT() // even if we don't show it, we need to load to show how many there are in toggle.
    }
    
    public func loadAfterWoT() {
        receiveNotification(.WoTReady)
            .sink { [weak self] notifciation in
                guard let self else { return }
                let pubkey = notifciation.object as! String
                self.load(pubkey: pubkey)
            }
            .store(in: &self.subscriptions)
    }
    
    public func markAcceptedAsRead() {
        objectWillChange.send()
        for conv in conversationRows {
            conv.unread = 0
        }
        bg().perform {
            for conv in self.conversationRows {
                conv.dmState.markedReadAt = Date.now
                conv.dmState.didUpdate.send()
            }
            DataProvider.shared().bgSave()
        }
    }
    
    public func markRequestsAsRead() {
        objectWillChange.send()
        for conv in requestRows {
            conv.unread = 0
        }
        bg().perform {
            for conv in self.requestRows {
                conv.dmState.markedReadAt = Date.now
                conv.dmState.didUpdate.send()
            }
            DataProvider.shared().bgSave()
        }
    }
    
    
    public func reloadAccepted() { _reloadAccepted.send() }
    private var _reloadAccepted = PassthroughSubject<Void, Never>()
    

    public func reloadMessageRequests() { _reloadMessageRequests.send() }
    private var _reloadMessageRequests = PassthroughSubject<Void, Never>()
    
    private func reloadMessageRequestsNotWot() { _reloadMessageRequestsNotWot.send() }
    private var _reloadMessageRequestsNotWot = PassthroughSubject<Void, Never>()
    
    private func loadAcceptedConversations() {
        guard let pubkey = self.pubkey else { return }
        let blockedPubkeys = blocks()
        
        bg().perform {
            var lastNotificationReceivedAt:Date? = nil
            
            let conversations = DMState.fetchByAccount(pubkey, context: bg())
                .filter { $0.accepted && !blockedPubkeys.contains($0.contactPubkey ?? "HMMICECREAMSOGOOD") }
            
            var conversationRows = [Conversation]()
            
            for conv in conversations {
                guard let accountPubkey = conv.accountPubkey, let contactPubkey = conv.contactPubkey
                else {
                    L.og.error("Conversation is missing account or contact pubkey, something wrong \(conv.debugDescription)")
                    continue
                }
                let mostRecentSent = Event.fetchMostRecentEventBy(pubkey: accountPubkey, andOtherPubkey: contactPubkey, andKind: 4, context: bg())
                
                // Not just most recent, but all so we can also count unread
                let allReceived = Event.fetchEventsBy(pubkey: contactPubkey, andKind: 4, context: bg())
                    .filter { $0.pTags().contains(where: { $0 == pubkey }) }
                
                let mostRecent = ([mostRecentSent] + allReceived)
                    .compactMap({ $0 })
                    .sorted(by: { $0.created_at > $1.created_at })
                    .first
                
                if let mostRecent, lastNotificationReceivedAt == nil { // set most recent if we dont have it set yet
                    lastNotificationReceivedAt = mostRecent.date
                }
                else if let mostRecent, let currentMostRecent = lastNotificationReceivedAt, mostRecent.date > currentMostRecent { // set if this one is more recent
                    lastNotificationReceivedAt = mostRecent.date
                }
                
                // Unread count is based on (in the following fallback order:
                // - 0 if last message is sent by own account
                // - Manual markedReadAt date
                // - Most recent DM sent (by own account) date
                // - Since beginning of time (all)
                
                let lastMessageByOwnAccount = mostRecent?.pubkey == pubkey
                
                let unreadSince = (conv.markedReadAt ?? (mostRecentSent?.date ?? Date(timeIntervalSince1970: 0)))
                
                let unread = lastMessageByOwnAccount
                ? 0
                : allReceived.filter { $0.date > unreadSince }.count
                
                var nrContact:NRContact?
                
                if let contact = Contact.fetchByPubkey(contactPubkey, context: bg()) {
                    nrContact = NRContact(contact: contact, following: isFollowing(contactPubkey))
                }
                
                guard let mostRecent = mostRecent else { continue }
                
                conversationRows
                    .append(Conversation(contactPubkey: contactPubkey, nrContact: nrContact, mostRecentMessage: mostRecent.noteText, mostRecentDate: mostRecent.date, mostRecentEvent: mostRecent, unread: unread, dmState: conv))
            }
            
            DispatchQueue.main.async {
                
                if let lastNotificationReceivedAt, self.lastNotificationReceivedAt == nil { // set most recent if we dont have it set yet
                    self.lastNotificationReceivedAt = lastNotificationReceivedAt
                }
                else if let lastNotificationReceivedAt, let currentMostRecent = self.lastNotificationReceivedAt, lastNotificationReceivedAt > currentMostRecent { // set if this one is more recent
                    self.lastNotificationReceivedAt = lastNotificationReceivedAt
                }
                
                self.conversationRows = conversationRows
                    .sorted(by: { $0.mostRecentDate > $1.mostRecentDate })
            }
        }
    }
    
    private func loadMessageRequests() {
        guard let pubkey = self.pubkey else { return }
        let blockedPubkeys = blocks()
        bg().perform {
            
            var lastNotificationReceivedAt:Date? = nil
            
            let conversations = DMState.fetchByAccount(pubkey, context: bg())
                .filter { !$0.accepted && !blockedPubkeys.contains($0.contactPubkey ?? "HMMICECREAMSOGOOD") }
                .filter { dmState in
                    if (!WOT_FILTER_ENABLED()) { return true }
                    guard let contactPubkey = dmState.contactPubkey else { return false }
                    return WebOfTrust.shared.isAllowed(contactPubkey)
                }
            
            var conversationRows = [Conversation]()
            
            for conv in conversations {
                guard let contactPubkey = conv.contactPubkey
                else {
                    L.og.error("Conversation is missing account or contact pubkey, something wrong \(conv.debugDescription)")
                    continue
                }
                
                // Not just most recent, but all so we can also count unread
                let allReceived = Event.fetchEventsBy(pubkey: contactPubkey, andKind: 4, context: bg())
                    .filter { $0.pTags().contains(where: { $0 == pubkey }) }

                let mostRecent = allReceived.first
                
                if let mostRecent, lastNotificationReceivedAt == nil { // set most recent if we dont have it set yet
                    lastNotificationReceivedAt = mostRecent.date
                }
                else if let mostRecent, let currentMostRecent = lastNotificationReceivedAt, mostRecent.date > currentMostRecent { // set if this one is more recent
                    lastNotificationReceivedAt = mostRecent.date
                }
                
                // Unread count is based on (in the following fallback order):
                // - Manual markedReadAt date
                // - Since beginning of time (all)
                                        
                let unreadSince = conv.markedReadAt ?? Date(timeIntervalSince1970: 0)
                
                let unread = allReceived.filter { $0.date > unreadSince }.count
                
                var nrContact:NRContact?
                
                if let contact = Contact.fetchByPubkey(contactPubkey, context: bg()) {
                    nrContact = NRContact(contact: contact, following: isFollowing(contactPubkey))
                }
                
                guard let mostRecent = mostRecent else { continue }
                
                conversationRows
                    .append(Conversation(contactPubkey: contactPubkey, nrContact: nrContact, mostRecentMessage: mostRecent.noteText, mostRecentDate: mostRecent.date, mostRecentEvent: mostRecent, unread: unread, dmState: conv))
            }

            DispatchQueue.main.async {
                
                if let lastNotificationReceivedAt, self.lastNotificationReceivedAt == nil { // set most recent if we dont have it set yet
                    self.lastNotificationReceivedAt = lastNotificationReceivedAt
                }
                else if let lastNotificationReceivedAt, let currentMostRecent = self.lastNotificationReceivedAt, lastNotificationReceivedAt > currentMostRecent { // set if this one is more recent
                    self.lastNotificationReceivedAt = lastNotificationReceivedAt
                }
                
                self.requestRows = conversationRows
                    .sorted(by: { $0.mostRecentDate > $1.mostRecentDate })
            }
        }
    }
    
    private func loadOutSideWoT() {
        guard WOT_FILTER_ENABLED() else { return }
        guard let pubkey = self.pubkey else { return }
        let blockedPubkeys = blocks()
        bg().perform {

            let conversations = DMState.fetchByAccount(pubkey, context: bg())
                .filter { !$0.accepted && !blockedPubkeys.contains($0.contactPubkey ?? "HMMICECREAMSOGOOD") }
                .filter { dmState in
                    guard let contactPubkey = dmState.contactPubkey else { return false }
                    return !WebOfTrust.shared.isAllowed(contactPubkey)
                }
            
            var conversationRows = [Conversation]()
            
            for conv in conversations {
                guard let contactPubkey = conv.contactPubkey
                else {
                    L.og.error("Conversation is missing account or contact pubkey, something wrong \(conv.debugDescription)")
                    continue
                }
                
                // Not just most recent, but all so we can also count unread
                let allReceived = Event.fetchEventsBy(pubkey: contactPubkey, andKind: 4, context: bg())
                    .filter { $0.pTags().contains(where: { $0 == pubkey }) }

                let mostRecent = allReceived.first
                
                // Unread count is based on (in the following fallback order):
                // - Manual markedReadAt date
                // - Since beginning of time (all)
                                        
                let unreadSince = conv.markedReadAt ?? Date(timeIntervalSince1970: 0)
                
                let unread = allReceived.filter { $0.date > unreadSince }.count
                
                var nrContact:NRContact?
                
                if let contact = Contact.fetchByPubkey(contactPubkey, context: bg()) {
                    nrContact = NRContact(contact: contact, following: isFollowing(contactPubkey))
                }
                
                guard let mostRecent = mostRecent else { continue }
                
                conversationRows
                    .append(Conversation(contactPubkey: contactPubkey, nrContact: nrContact, mostRecentMessage: mostRecent.noteText, mostRecentDate: mostRecent.date, mostRecentEvent: mostRecent, unread: unread, dmState: conv))
            }

            DispatchQueue.main.async {
                self.requestRowsNotWoT = conversationRows
                    .sorted(by: { $0.mostRecentDate > $1.mostRecentDate })
            }
        }
    }
    
    public func newMessage(_ dmState:DMState) {
        reloadAccepted()
        reloadMessageRequests()
        reloadMessageRequestsNotWot()
        
    }
    
    private func monthsAgoRange(_ months:Int) -> (since: Int, until: Int) {
        return (
            since: NTimestamp(date: Date().addingTimeInterval(Double(months + 1) * -30 * 24 * 60 * 60)).timestamp,
            until: NTimestamp(date: Date().addingTimeInterval(Double(months) * -30 * 24 * 60 * 60)).timestamp
        )
    }
    
    @Published var scanningMonthsAgo = 0
    
    public func rescanForMissingDMs(_ monthsAgo: Int) {
        guard let pubkey else { return }
        guard scanningMonthsAgo == 0 else { return }
        
        for i in 0...monthsAgo {
            let ago = monthsAgoRange(monthsAgo - i)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(5 * i)) {
                self.scanningMonthsAgo = i+1 == (monthsAgo + 1) ? 0 : i+1
                
                if let message = CM(
                    type: .REQ,
                    filters: [
                        // DMs sent
                        Filters(authors: Set([pubkey]), kinds: [4], since: ago.since, until: ago.until),
                        // DMs received
                        Filters(kinds: [4], tagFilter: TagFilter(tag: "p", values: [pubkey]), since: ago.since, until: ago.until)
                    ]
                ).json() {
                    req(message)
                }
            }
        }
    }
}
