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
    var callbackSubscriptionIds = Set<String>()
    var sendReceivedNotification = PassthroughSubject<Void, Never>()
    
    public var importedMessagesFromSubscriptionIds = PassthroughSubject<Set<String>, Never>()
    public var importedPrioMessagesFromSubscriptionId = PassthroughSubject<ImportedPrioNotification, Never>()
    public var newEventsInDatabase = PassthroughSubject<Void, Never>()
    public var contactSaved = PassthroughSubject<String, Never>()
    public var listStatus = PassthroughSubject<String, Never>()
    
    var existingIds: [String: EventState] = [:]
    var didPreload = false // Main context
    
    static let shared = Importer()
    
    let decoder = JSONDecoder()
    var nwcConnection:NWCConnection?
    private var bgContext: NSManagedObjectContext
    
    init() {
        bgContext = bg()
        triggerImportWhenRelayMessagesAreAdded()
        sendReceivedNotifications()
    }
    
    func sendReceivedNotifications() {
        sendReceivedNotification
            .debounce(for: .seconds(0.15), scheduler: DispatchQueue.global())
            .throttle(for: 0.5, scheduler: DispatchQueue.global(), latest: true)
            .receive(on: DispatchQueue.global())
            .sink { [weak self] in
                self?.bgContext.perform { [weak self] in
                    guard let self else { return }
                    L.importing.debug("🏎️🏎️ sendReceivedNotifications() after duplicate received (callbackSubscriptionIds: \(self.callbackSubscriptionIds.count)) ")
                    let notified = self.callbackSubscriptionIds
                    self.importedMessagesFromSubscriptionIds.send(notified)
                    self.callbackSubscriptionIds = []
                }
            }
            .store(in: &subscriptions)
    }
    
    func triggerImportWhenRelayMessagesAreAdded() {
        addedRelayMessage
            .debounce(for: .seconds(0.15), scheduler: DispatchQueue.global())
            .throttle(for: 0.5, scheduler: DispatchQueue.global(), latest: true)
            .receive(on: DispatchQueue.global())
            .sink { [weak self] in
                L.importing.debug("🏎️🏎️ importEvents() after relay message received (throttle = 0.5 seconds), but sends first after debounce (0.15)")
                self?.importEvents()
            }
            .store(in: &subscriptions)
        
        addedPrioRelayMessage
            .debounce(for: .seconds(0.05), scheduler: DispatchQueue.global())
            .throttle(for: 0.25, scheduler: DispatchQueue.global(), latest: true)
            .receive(on: DispatchQueue.global())
            .sink { [weak self] in
                L.importing.debug("🏎️🏎️ importEvents() (PRIO) after relay message received (throttle = 0.25 seconds), but sends first after debounce (0.05)")
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
            fr.propertiesToFetch = ["id", "relays"]
            
            if let results = try? bgContext.fetch(fr) {
                let existingIds = results.reduce(into: [String: EventState]()) { (dict, event) in
                    dict[event.id] = EventState(status: .SAVED, relays: event.relays)
                }
                self.existingIds = existingIds
                L.og.debug("\(self.existingIds.count) existing ids added to cache")
            }
        }
    }
    
    // 876.00 ms    5.3%    0 s                   closure #1 in Importer.importEvents()
    public func importEvents() {
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
                L.importing.debug("🏎️🏎️ importEvents() nothing to import.")
                self.isImporting = false; return }
            
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
                            L.importing.info("🔴🔴😡😡 hey invalid sig yo 😡😡")
                            continue
                        }
                    }
                    
                    if message.subscriptionId == "Profiles" && event.kind == .setMetadata {
                        account()?.lastProfileReceivedAt = Date.now
                    }
                                        
                    guard existingIds[event.id]?.status != .SAVED else {
                        alreadyInDBskipped = alreadyInDBskipped + 1
                        if event.publicKey == NRState.shared.activeAccountPublicKey && event.kind == .contactList { // To enable Follow button we need to have received a contact list
                            DispatchQueue.main.async {
                                FollowingGuardian.shared.didReceiveContactListThisSession = true
                            }
                        }
                        Event.updateRelays(event.id, relays: message.relays, context: bgContext)
                        var alreadySavedSubs = Set<String>()
                        if let subscriptionId = message.subscriptionId {
                            alreadySavedSubs.insert(subscriptionId)
                        }
                        self.importedMessagesFromSubscriptionIds.send(alreadySavedSubs)
                        continue
                    }                    
                    
                    // Skip if we already have a newer kind 3
                    if  event.kind == .contactList,
                        let existingKind3 = Event.fetchReplacableEvent(3, pubkey: event.publicKey, context: bgContext),
                        existingKind3.created_at > Int64(event.createdAt.timestamp)
                    {
                        if event.publicKey == NRState.shared.activeAccountPublicKey && event.kind == .contactList { // To enable Follow button we need to have received a contact list
                            DispatchQueue.main.async {
                                FollowingGuardian.shared.didReceiveContactListThisSession = true
                            }
                        }
                        continue
                    }
                    
                    var kind6firstQuote: Event?
                    if event.kind == .repost && (event.content.prefix(2) == #"{""# || event.content == "") {
                        if event.content == "" {
                            if let firstE = event.firstE() {
                                // TODO: Should be able to use existingIds here...
                                kind6firstQuote = try? Event.fetchEvent(id: firstE, context: bgContext)
                            }
                        }
                        else if let noteInNote = try? decoder.decode(NEvent.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) {
                            if !Event.eventExists(id: noteInNote.id, context: bgContext) { // TODO: check existingIds instead of .eventExists
                                kind6firstQuote = Event.saveEvent(event: noteInNote, relays: message.relays, context: bgContext)
                                
                                if let kind6firstQuote = kind6firstQuote {
//                                    kind6firstQuote.repostsCount = 1
                                    NotificationsViewModel.shared.checkNeedsUpdate(kind6firstQuote)
                                }
                            }
                            else {
                                Event.updateRelays(noteInNote.id, relays: message.relays, context: bgContext)
                            }
                        }
                    }
                    
                    if event.kind == .contactList {
                        if event.publicKey == EXPLORER_PUBKEY {
                            // use guest account p's for "Explorer" feed
                            let pTags = event.pTags()
                            Task { @MainActor in
                                NRState.shared.rawExplorePubkeys = Set(pTags)
                            }
                        }
                        if event.publicKey == NRState.shared.activeAccountPublicKey && event.kind == .contactList { // To enable Follow button we need to have received a contact list
                            DispatchQueue.main.async {
                                FollowingGuardian.shared.didReceiveContactListThisSession = true
                            }
                        }

                        
                        // Send new following list notification, but skip if it is for building the Web of Trust
                        if let subId = message.subscriptionId, subId.prefix(7) != "WoTFol-" {
                            let n = event
                            DispatchQueue.main.async {
                                sendNotification(.newFollowingListFromRelay, n)
                            }
                        }
                    }
                    
                    // 493.00 ms    3.0%    1.00 ms specialized static Event.saveEvent(event:relays:flags:kind6firstQuote:context:)
                    let savedEvent = Event.saveEvent(event: event, relays: message.relays, kind6firstQuote: kind6firstQuote, context: bgContext) // Thread 927: "Illegal attempt to establish a relationship 'reactionTo' between objects in different contexts
                        // "Illegal attempt to establish a relationship 'firstQuote' between objects in different contexts
                    NotificationsViewModel.shared.checkNeedsUpdate(savedEvent)
                    saved = saved + 1
                    if let subscriptionId = message.subscriptionId {
                        subscriptionIds.insert(subscriptionId)
                    }
                    if (kind6firstQuote != nil) {
                        savedEvent.firstQuote = kind6firstQuote
                    }
                    
                    if event.kind == .setMetadata {
                        Contact.saveOrUpdateContact(event: event)
                    }
                    
                    
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                    if event.kind == .reaction {
                        do { try _ = Event.updateLikeCountCache(savedEvent, content: event.content, context: bgContext) } catch {
                            L.importing.error("🦋🦋🔴🔴🔴 problem updating Like Count Cache .id \(event.id)")
                        }
                        if let otherPubkey = savedEvent.otherPubkey, NRState.shared.accountPubkeys.contains(otherPubkey) {
                            // TODO: Check if this works for own accounts, because import doesn't happen when saved local first?
                            ViewUpdates.shared.feedUpdates.send(FeedUpdate(type: .Reactions, accountPubkey: otherPubkey))
                        }
                        if let reactionToId = savedEvent.reactionToId {
                            ViewUpdates.shared.relatedUpdates.send(RelatedUpdate(type: .Reactions, eventId: reactionToId))
                        }
                    }
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                    if event.kind == .zapNote {
                        let _ = Event.updateZapTallyCache(savedEvent, context: bgContext)
                        
                        if let otherPubkey = savedEvent.otherPubkey, NRState.shared.accountPubkeys.contains(otherPubkey) {
                            // TODO: Check if this works for own accounts, because import doesn't happen when saved local first?
                            ViewUpdates.shared.feedUpdates.send(FeedUpdate(type: .Zaps, accountPubkey: otherPubkey))
                        }
                        
                        if let zappedEventId = savedEvent.zappedEventId {
                            ViewUpdates.shared.relatedUpdates.send(RelatedUpdate(type: .Zaps, eventId: zappedEventId))
                        }
                    }
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REPLIES, MENTIONS)
                    if event.kind == .textNote || event.kind == .repost {
                        // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
                        do { try _ = Event.updateMentionsCountCache(event.tags, context: bgContext) } catch {
                            L.importing.error("🦋🦋🔴🔴🔴 problem updateMentionsCountCache .id \(event.id)")
                        }
                    }
                    
                    // batch save every 100
                    if count % 100 == 0 {
                        if (bgContext.hasChanges) {
                            do {
                                try bgContext.save()
                                L.importing.debug("💾💾 Saved \(count)/\(forImportsCount)")
                                let mainQueueCount = count
                                let mainQueueForImportsCount = forImportsCount
                                self.importedMessagesFromSubscriptionIds.send(subscriptionIds)
                                self.newEventsInDatabase.send()
                                self.listStatus.send("Processing \(mainQueueCount)/\(max(mainQueueCount,mainQueueForImportsCount)) items...")
                                subscriptionIds.removeAll()
                            }
                            catch {
                                L.importing.error("🏎️🏎️ 🔴🔴🔴 Error on batch \(count)/\(forImportsCount): \(error)")
                            }
                        }
                    }
                }
                if (bgContext.hasChanges) {
                    try bgContext.save()
                    if (saved > 0) {
                        L.importing.debug("💾💾 Processed: \(forImportsCount), saved: \(saved), skipped (db): \(alreadyInDBskipped)")
                        let mainQueueCount = count
                        let mainQueueForImportsCount = forImportsCount
                        self.importedMessagesFromSubscriptionIds.send(subscriptionIds)
                        self.newEventsInDatabase.send()
                        self.listStatus.send("Processing \(mainQueueCount)/\(max(mainQueueCount,mainQueueForImportsCount)) items...")
                        subscriptionIds.removeAll()
                    }
                    else {
                        L.importing.debug("💾   Finished, nothing saved. -- Processed: \(forImportsCount), saved: \(saved), skipped (db): \(alreadyInDBskipped)")
                    }
                }
                else {
                    L.importing.debug("🏎️🏎️ Nothing imported, no changes in \(count) messages")
                    if count > 50 {
                        sendNotification(.noNewEventsInDatabase)
                    }
                }
            }
            catch {
                L.importing.error("🏎️🏎️🔴🔴🔴🔴 Failed to import because: \(error)")
            }
            self.isImporting = false
            if (self.needsImport) {
                L.importing.debug("🏎️🏎️ Chaining next import ")
                self.needsImport = false
                self.importEvents()
            }
            else {
                bgSave()
            }
        }
    }
    
    public func importPrioEvents() {
        bgContext.perform { [unowned self] in
            let forImportsCount = MessageParser.shared.priorityBucket.count
            guard forImportsCount != 0 else {
                L.importing.debug("🏎️🏎️ importPrioEvents() nothing to import.")
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
                        L.importing.error("🔴🔴 message.event is nil \(message.message)")
                        continue
                    }
                    
                    if (MessageParser.shared.isSignatureVerificationEnabled) {
                        guard try event.verified() else {
                            L.importing.info("🔴🔴😡😡 hey invalid sig yo 😡😡")
                            continue
                        }
                    }
                                         
                    guard existingIds[event.id]?.status != .SAVED else {
                        alreadyInDBskipped = alreadyInDBskipped + 1
                        if event.publicKey == NRState.shared.activeAccountPublicKey && event.kind == .contactList { // To enable Follow button we need to have received a contact list
                            DispatchQueue.main.async {
                                FollowingGuardian.shared.didReceiveContactListThisSession = true
                            }
                        }
                        Event.updateRelays(event.id, relays: message.relays, context: bgContext)
                        var alreadySavedSubs = Set<String>()
                        if let subscriptionId = message.subscriptionId {
                            alreadySavedSubs.insert(subscriptionId)
                        }
                        continue
                    }
                    // Skip if we already have a newer kind 3
                    if  event.kind == .contactList,
                        let existingKind3 = Event.fetchReplacableEvent(3, pubkey: event.publicKey, context: bgContext),
                        existingKind3.created_at > Int64(event.createdAt.timestamp)
                    {
                        if event.publicKey == NRState.shared.activeAccountPublicKey && event.kind == .contactList { // To enable Follow button we need to have received a contact list
                            DispatchQueue.main.async {
                                FollowingGuardian.shared.didReceiveContactListThisSession = true
                            }
                        }
                        continue
                    }
                    
                    var kind6firstQuote: Event?
                    if event.kind == .repost && (event.content.prefix(2) == #"{""# || event.content == "") {
                        if event.content == "" {
                            if let firstE = event.firstE() {
                                // TODO: Should be able to use existingIds here...
                                kind6firstQuote = try? Event.fetchEvent(id: firstE, context: bgContext)
                            }
                        }
                        else if let noteInNote = try? decoder.decode(NEvent.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) {
                            if !Event.eventExists(id: noteInNote.id, context: bgContext) { // TODO: check existingIds instead of .eventExists
                                kind6firstQuote = Event.saveEvent(event: noteInNote, relays: message.relays, context: bgContext)
                                
                                if let kind6firstQuote = kind6firstQuote {
//                                    kind6firstQuote.repostsCount = 1 
                                    NotificationsViewModel.shared.checkNeedsUpdate(kind6firstQuote)
                                }
                            }
                            else {
                                Event.updateRelays(noteInNote.id, relays: message.relays, context: bgContext)
                            }
                        }
                    }
                    
                    if event.kind == .contactList {
                        if event.publicKey == EXPLORER_PUBKEY {
                            // use guest account p's for "Explorer" feed
                            let pTags = event.pTags()
                            Task { @MainActor in
                                NRState.shared.rawExplorePubkeys = Set(pTags)
                            }
                        }
                        if event.publicKey == NRState.shared.activeAccountPublicKey && event.kind == .contactList { // To enable Follow button we need to have received a contact list
                            DispatchQueue.main.async {
                                FollowingGuardian.shared.didReceiveContactListThisSession = true
                            }
                        }

                        
                        // Send new following list notification, but skip if it is for building the Web of Trust
                        if let subId = message.subscriptionId, subId.prefix(7) != "WoTFol-" {
                            let n = event
                            DispatchQueue.main.async {
                                sendNotification(.newFollowingListFromRelay, n)
                            }
                        }
                    }
                    
                    // 493.00 ms    3.0%    1.00 ms specialized static Event.saveEvent(event:relays:flags:kind6firstQuote:context:)
                    let savedEvent = Event.saveEvent(event: event, relays: message.relays, kind6firstQuote:kind6firstQuote, context: bgContext)
                    NotificationsViewModel.shared.checkNeedsUpdate(savedEvent)
                    saved = saved + 1
                    if let subscriptionId = message.subscriptionId {
                        importedPrioMessagesFromSubscriptionId.send(ImportedPrioNotification(subscriptionId: subscriptionId, event: savedEvent))
                    }
                    if (kind6firstQuote != nil) {
                        savedEvent.firstQuote = kind6firstQuote
                    }
                    
                    if event.kind == .setMetadata {
                        Contact.saveOrUpdateContact(event: event)
                    }
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                    if event.kind == .reaction {
                        do { try _ = Event.updateLikeCountCache(savedEvent, content:event.content, context: bgContext) } catch {
                            L.importing.error("🦋🦋🔴🔴🔴 problem updating Like Count Cache .id \(event.id)")
                        }
                        if let otherPubkey = savedEvent.otherPubkey, NRState.shared.accountPubkeys.contains(otherPubkey) {
                            // TODO: Check if this works for own accounts, because import doesn't happen when saved local first?
                            ViewUpdates.shared.feedUpdates.send(FeedUpdate(type: .Reactions, accountPubkey: otherPubkey))
                        }
                        
                        if let reactionToId = savedEvent.reactionToId {
                            ViewUpdates.shared.relatedUpdates.send(RelatedUpdate(type: .Reactions, eventId: reactionToId))
                        }
                    }
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                    if event.kind == .zapNote {
                        let _ = Event.updateZapTallyCache(savedEvent, context: bgContext)
                        
                        if let otherPubkey = savedEvent.otherPubkey, NRState.shared.accountPubkeys.contains(otherPubkey) {
                            // TODO: Check if this works for own accounts, because import doesn't happen when saved local first?
                            ViewUpdates.shared.feedUpdates.send(FeedUpdate(type: .Zaps, accountPubkey: otherPubkey))
                        }
                        
                        if let zappedEventId = savedEvent.zappedEventId {
                            ViewUpdates.shared.relatedUpdates.send(RelatedUpdate(type: .Zaps, eventId: zappedEventId))
                        }
                    }
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REPLIES, MENTIONS)
                    if event.kind == .textNote || event.kind == .repost {
                        // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
                        do { try _ = Event.updateMentionsCountCache(event.tags, context: bgContext) } catch {
                            L.importing.error("🦋🦋🔴🔴🔴 problem updateMentionsCountCache .id \(event.id)")
                        }
                    }
                }
                if (bgContext.hasChanges) {
                    try bgContext.save()
                }
                else {
                    L.importing.debug("🏎️🏎️ Nothing imported, no changes in new prio message")
                }
            }
            catch {
                L.importing.error("🏎️🏎️🔴🔴🔴🔴 Failed to import because: \(error)")
            }

            bgSave()
        }
    }
}
