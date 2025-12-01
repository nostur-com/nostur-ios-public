//
//  Importer.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/01/2023.
//

import Foundation
import OSLog
import CoreData
import Combine
import NostrEssentials

struct EventState {
    let status: ProcessStatus
    var relays: String?
}

enum ProcessStatus {
    case UNKNOWN
    case RECEIVED
    case PARSED
    case SAVED
}

class Importer {
    
    var isImporting = false
    var isImportingPrio = false
    var needsImport = false
    var subscriptions = Set<AnyCancellable>()
    var addedRelayMessage = PassthroughSubject<Void, Never>()
    var addedPrioRelayMessage = PassthroughSubject<Void, Never>()
    var shouldBeDelaying = false
    var delayProcessingSub = PassthroughSubject<Void, Never>()
    var callbackSubscriptionIds = Set<String>()
    var sendReceivedNotification = PassthroughSubject<Void, Never>()
    
    public var importedMessagesFromSubscriptionIds = PassthroughSubject<Set<String>, Never>()
    public var importedPrioMessagesFromSubscriptionId = PassthroughSubject<ImportedPrioNotification, Never>()
    public var listStatus = PassthroughSubject<String, Never>()
    
    var existingIds: [String: EventState] = [:]
    var didPreload = false // Main context
    
    static let shared = Importer()
    
    let decoder = JSONDecoder()
    var nwcConnection:NWCConnection?
    private var bgContext: NSManagedObjectContext
    private var relationFixer: CoreDataRelationFixer
    
    private init() {
        relationFixer = CoreDataRelationFixer.shared
        bgContext = bg()
        triggerImportWhenRelayMessagesAreAdded()
        sendReceivedNotifications()
        setupDelayProcessing()
    }
    
    public func delayProcessing() {
        shouldBeDelaying = true
        delayProcessingSub.send()
    }
    
    private func setupDelayProcessing() {
        delayProcessingSub
            .debounce(for: .seconds(5.0), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.shouldBeDelaying = false
                self?.addedRelayMessage.send()
            }
            .store(in: &subscriptions)
    }
    

    
    
    func sendReceivedNotifications() {
        sendReceivedNotification
            .debounce(for: .seconds(0.075), scheduler: DispatchQueue.global())
            .throttle(for: 0.25, scheduler: DispatchQueue.global(), latest: true)
            .receive(on: DispatchQueue.global())
            .sink { [weak self] in
                self?.bgContext.perform { [weak self] in
                    guard let self else { return }
#if DEBUG
                    L.importing.debug("🏎️🏎️ sendReceivedNotifications() after duplicate received (callbackSubscriptionIds: \(self.callbackSubscriptionIds.count)) -[LOG]-")
#endif
                    let notified = self.callbackSubscriptionIds
                    self.importedMessagesFromSubscriptionIds.send(notified)
                    self.callbackSubscriptionIds = []
                }
            }
            .store(in: &subscriptions)
    }
    
    func triggerImportWhenRelayMessagesAreAdded() {
        addedRelayMessage
            .debounce(for: .seconds(0.05), scheduler: DispatchQueue.global())
            .throttle(for: 0.125, scheduler: DispatchQueue.global(), latest: true)
            .receive(on: DispatchQueue.global())
            .sink { [weak self] in
#if DEBUG
                L.importing.debug("🏎️🏎️ importEvents() after relay message received (throttle = 0.125 seconds), but sends first after debounce (0.05) -[LOG]-")
#endif
                self?.importEvents()
            }
            .store(in: &subscriptions)
        
        addedPrioRelayMessage
            .debounce(for: .seconds(0.05), scheduler: DispatchQueue.global())
            .throttle(for: 0.075, scheduler: DispatchQueue.global(), latest: true)
            .receive(on: DispatchQueue.global())
            .sink { [weak self] in
#if DEBUG
                L.importing.debug("🏎️🏎️ importEvents() (PRIO) after relay message received (throttle = 0.075 seconds), but sends first after debounce (0.05) -[LOG]-")
#endif
                self?.importPrioEvents()
            }
            .store(in: &subscriptions)
    }
    
    
    // Load all kind 3 ids, these are expensive to parse
    // and load recent 5000
    // Might as well just load all??? Its fast anyway
    func preloadExistingIdsCache() async {
        didPreload = true
        await bgContext.perform { [weak self] in
            guard let self else { return }
            
            let fr = Event.fetchRequest()
            fr.fetchLimit = 1_000_000
            fr.propertiesToFetch = ["id", "relays", "otherId", "kind"]
            
            if let results = try? bgContext.fetch(fr) {
                let existingIds = results.reduce(into: [String: EventState]()) { (dict, event) in
                    if event.kind == 1059, let otherId = event.otherId { // Rumor events we store the outer wrap id as .SAVED so we don't unwrap again
                        dict[otherId] = EventState(status: .SAVED, relays: event.relays)
                    }
                    else {
                        dict[event.id] = EventState(status: .SAVED, relays: event.relays)
                    }
                    
                }
                self.existingIds = existingIds
#if DEBUG
                L.og.debug("\(self.existingIds.count) existing ids added to cache")
#endif
            }
        }
    }
    
    // 876.00 ms    5.3%    0 s                   closure #1 in Importer.importEvents()
    public func importEvents() {
        guard !shouldBeDelaying else {
#if DEBUG
            L.og.debug("🏎️🏎️ importEvents -- delaying")
#endif
            return
        }
        bgContext.perform { [unowned self] in
            if (self.isImporting) {
                let itemsCount = MessageParser.shared.messageBucket.count
                self.needsImport = true
                if itemsCount > 0 {
                    self.listStatus.send("Processing \(itemsCount) items...")
                }
                return
            }
            
            if (self.isImportingPrio) {
                self.needsImport = true
                return
            }
            
            self.isImporting = true
            let forImportsCount = MessageParser.shared.messageBucket.count
            guard forImportsCount != 0 else {
#if DEBUG
                L.importing.debug("🏎️🏎️ importEvents() nothing to import.")
#endif
                self.isImporting = false
                return
            }
            
            self.listStatus.send("Processing \(forImportsCount) items...")
            
            do {
                var count = 0
                var alreadyInDBskipped = 0
                var saved = 0
                
                // We send a notification every .save with the saved subscriptionIds
                // so other parts of the system can start fetching from local db
                var subscriptionIds = Set<String>()
                while let message = MessageParser.shared.messageBucket.popFirst() {
                    count = count + 1
                    guard let event = message.event else {
                        L.importing.error("🔴🔴 message.event is nil \(message.message)")
                        continue
                    }
                    
                    if (MessageParser.shared.isSignatureVerificationEnabled) {
                        guard try event.verified() else {
#if DEBUG
                            L.importing.info("🔴🔴😡😡 hey invalid sig yo 😡😡")
#endif
                            continue
                        }
                    }
                    
                    if message.subscriptionId == "Profiles" && event.kind == .setMetadata {
                        account()?.lastProfileReceivedAt = Date.now
                    }
                                     
                    // Event should not already be .SAVED, else we skip. But do check for our own contact list received to enable Follow buttons
                    guard existingIds[event.id]?.status != .SAVED else {
                        alreadyInDBskipped = alreadyInDBskipped + 1
                        // TODO: This needs improvement for multi-account handling
                        if event.publicKey == AccountsState.shared.activeAccountPublicKey && event.kind == .contactList { // To enable Follow button we need to have received a contact list
                            DispatchQueue.main.async {
                                FollowingGuardian.shared.didReceiveContactListThisSession = true
#if DEBUG
                                L.og.info("🙂🙂 FollowingGuardian.didReceiveContactListThisSession")
#endif
                            }
                        }
                        Event.updateRelays(event.id, relays: message.relays, isWrapId: event.kind.id == 1059, context: bgContext)
                        var alreadySavedSubs = Set<String>()
                        if let subscriptionId = message.subscriptionId {
                            alreadySavedSubs.insert(subscriptionId)
                        }
                        self.importedMessagesFromSubscriptionIds.send(alreadySavedSubs)
                        
                        // For live chat rooms
                        if event.kind == .zapNote || event.kind == .chatMessage {
                            DispatchQueue.main.async { // TODO: Need to check how to handle .receivedMessage in case of GiftWrap (so far not needed, yet)
                                sendNotification(.receivedMessage, message)
                            }
                        }
                        continue
                    }                    

                    do {
                        if event.kind == .giftWrap { // TODO: Need to check how to handle .receivedMessage in case of GiftWrap (so far not needed, yet)
                            // Can we decrypt? (Do we have account with private key?)
                            guard let targetPubkey = event.firstP(), AccountsState.shared.bgFullAccountPubkeys.contains(targetPubkey) else { continue }
                            guard let privKey = AccountManager.shared.getPrivateKeyHex(pubkey: targetPubkey), let keys = try? NostrEssentials.Keys(privateKeyHex: privKey) else { continue }
                            
                
                            // Unwrap then handle rumor like normal event
                            let (rumor, seal) = try unwrapGift(event.toNostrEssentialsEvent(), ourKeys: keys)
                            
                            // Do we support the rumor kind?
                            guard SUPPORTED_RUMOR_KINDS.contains(rumor.kind) else { continue }
                            
                            // Import rumor
                            _ = try importEvent(event: NEvent.fromNostrEssentialsEvent(rumor), wrapId: event.id, message: message)
                        }
                        else {
                            // handle like normal
                            _ = try importEvent(event: event, message: message)
                        }
                        saved = saved + 1
                        if let subscriptionId = message.subscriptionId {
                            subscriptionIds.insert(subscriptionId)
                        }
                    } catch { // Continue with next event
                        continue
                    }
                    
                    if count % 100 == 0 {
#if DEBUG
                        L.importing.debug("💾💾 Processed \(count)/\(forImportsCount)")
#endif
                        let mainQueueCount = count
                        let mainQueueForImportsCount = forImportsCount
                        self.importedMessagesFromSubscriptionIds.send(subscriptionIds)
                        self.listStatus.send("Processing \(mainQueueCount)/\(max(mainQueueCount,mainQueueForImportsCount)) items...")
                        subscriptionIds.removeAll()
                    }
                }
                if (saved > 0) {
#if DEBUG
                    L.importing.debug("💾💾 Processed: \(forImportsCount), skipped (db): \(alreadyInDBskipped) -[LOG]-")
#endif
                    let mainQueueCount = count
                    let mainQueueForImportsCount = forImportsCount
                    self.importedMessagesFromSubscriptionIds.send(subscriptionIds)
                    self.listStatus.send("Processing \(mainQueueCount)/\(max(mainQueueCount,mainQueueForImportsCount)) items...")
                    subscriptionIds.removeAll()
                }
                else {
#if DEBUG
                    L.importing.debug("💾   Finished, nothing saved. -- Processed: \(forImportsCount), skipped (db): \(alreadyInDBskipped) -[LOG]-")
#endif
                }
            }
            catch {
                L.importing.error("🏎️🏎️🔴🔴🔴🔴 Failed to import because: \(error)")
            }
            self.isImporting = false
            if (self.needsImport) {
#if DEBUG
                L.importing.debug("🏎️🏎️ Chaining next import ")
#endif
                self.needsImport = false
                self.importEvents()
            }
            else {
                DataProvider.shared().saveToDisk()
            }
        }
    }
    
    public func importPrioEvents() {
        bgContext.perform { [unowned self] in
            let forImportsCount = MessageParser.shared.priorityBucket.count
            guard forImportsCount != 0 else {
#if DEBUG
                L.importing.debug("🏎️🏎️ importPrioEvents() nothing to import.")
#endif
                return
            }
            self.listStatus.send("Processing \(forImportsCount) items...")
            do {
                var count = 0
                var alreadyInDBskipped = 0
                var saved = 0
                
                while let message = MessageParser.shared.priorityBucket.popFirst() {
                    count = count + 1
                    guard let event = message.event else {
#if DEBUG
                        L.importing.error("🔴🔴 message.event is nil \(message.message)")
#endif
                        continue
                    }
                    
                    if (MessageParser.shared.isSignatureVerificationEnabled) {
                        guard try event.verified() else {
#if DEBUG
                            L.importing.info("🔴🔴😡😡 hey invalid sig yo 😡😡")
#endif
                            continue
                        }
                    }
                                         
                    guard existingIds[event.id]?.status != .SAVED else {
                        alreadyInDBskipped = alreadyInDBskipped + 1
                        if event.publicKey == AccountsState.shared.activeAccountPublicKey && event.kind == .contactList { // To enable Follow button we need to have received a contact list
                            DispatchQueue.main.async {
                                FollowingGuardian.shared.didReceiveContactListThisSession = true
#if DEBUG
                                L.og.info("🙂🙂 FollowingGuardian.didReceiveContactListThisSession")
#endif
                            }
                        }
                        Event.updateRelays(event.id, relays: message.relays, isWrapId: event.kind.id == 1059, context: bgContext)
                        var alreadySavedSubs = Set<String>()
                        if let subscriptionId = message.subscriptionId {
                            alreadySavedSubs.insert(subscriptionId)
                        }
                        continue
                    }
                    
                    do {
                        if event.kind == .giftWrap { // TODO: Need to check how to handle .receivedMessage in case of GiftWrap (so far not needed, yet)
                            // Can we decrypt? (Do we have account with private key?)
                            guard let targetPubkey = event.firstP(), AccountsState.shared.bgFullAccountPubkeys.contains(targetPubkey) else { continue }
                            guard let privKey = AccountManager.shared.getPrivateKeyHex(pubkey: targetPubkey), let keys = try? NostrEssentials.Keys(privateKeyHex: privKey) else { continue }
                            
                
                            // Unwrap then handle rumor like normal event
                            let (rumor, seal) = try unwrapGift(event.toNostrEssentialsEvent(), ourKeys: keys)
                            
                            // Do we support the rumor kind?
                            guard SUPPORTED_RUMOR_KINDS.contains(rumor.kind) else { continue }
                            
                            // Import rumor
                            let savedEvent = try importEvent(event: NEvent.fromNostrEssentialsEvent(rumor), wrapId: event.id, message: message)
                            
                            // Immediately notify (prio)
                            if let subscriptionId = message.subscriptionId {
                                importedPrioMessagesFromSubscriptionId.send(ImportedPrioNotification(subscriptionId: subscriptionId, event: savedEvent))
                            }
                        }
                        else {
                            // handle like normal
                            let savedEvent = try importEvent(event: event, message: message)
                            
                            // Immediately notify (prio)
                            if let subscriptionId = message.subscriptionId {
                                importedPrioMessagesFromSubscriptionId.send(ImportedPrioNotification(subscriptionId: subscriptionId, event: savedEvent))
                            }
                        }
                        saved = saved + 1
                    } catch { // Continue with next event
                        continue
                    }
                }
            }
            catch {
                L.importing.error("🏎️🏎️🔴🔴🔴🔴 Failed to import because: \(error)")
            }

            DataProvider.shared().saveToDisk()
        }
    }
    
    
    private func importEvent(event: NEvent, wrapId: String? = nil, message: RelayMessage) throws -> Event {
        // Skip if we already have a newer kind 3
        if  event.kind == .contactList,
            let existingKind3 = Event.fetchReplacableEvent(3, pubkey: event.publicKey, context: bgContext),
            existingKind3.created_at > Int64(event.createdAt.timestamp)
        {
            if event.publicKey == AccountsState.shared.activeAccountPublicKey && event.kind == .contactList { // To enable Follow button we need to have received a contact list
                DispatchQueue.main.async {
                    FollowingGuardian.shared.didReceiveContactListThisSession = true
#if DEBUG
                    L.og.info("🙂🙂 FollowingGuardian.didReceiveContactListThisSession")
#endif
                }
            }
            throw ImportErrors.AlreadyHaveNewerReplacableEvent
        }
        
        var kind6firstQuote: Event?
        kind6firstQuote = try handleRepost(event, relays: message.relays, bgContext: bgContext)
        try handlePinnedPosts(event, relays: message.relays, bgContext: bgContext)

        handleContactList(event, subscriptionId: message.subscriptionId)
        
        let savedEvent = Event.saveEvent(event: event, relays: message.relays, kind6firstQuote: kind6firstQuote, wrapId: wrapId, context: bgContext)
        FeedsCoordinator.shared.notificationNeedsUpdateSubject.send(
            NeedsUpdateInfo(event: savedEvent)
        )
                     
        // FOR LIVE CHATS THAT ARE NOT IN DB
        if event.kind == .zapNote {
            DispatchQueue.main.async { // TODO: Need to check how to handle .receivedMessage in case of GiftWrap (so far not needed, yet)
                sendNotification(.receivedMessage, message)
            }
        }
        return savedEvent
    }
}

let SUPPORTED_RUMOR_KINDS = Set<Int>([1,20,9802,1111,1222,1244,14,7,30311])
