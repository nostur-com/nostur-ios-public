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
    let status:ProcessStatus
    var relays:String?
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
    
    var importedMessagesFromSubscriptionIds = PassthroughSubject<Set<String>, Never>()
    
    var existingIds:[String: EventState] = [:]
    
    static let shared = Importer()
    
    let decoder = JSONDecoder()
    var nwcConnection:NWCConnection?
    
    init() {
        triggerImportWhenRelayMessagesAreAdded()
        sendReceivedNotifications()
    }
    
    func sendReceivedNotifications() {
        sendReceivedNotification
            .debounce(for: .seconds(0.15), scheduler: DispatchQueue.global())
            .throttle(for: 0.5, scheduler: DispatchQueue.global(), latest: true)
            .receive(on: DispatchQueue.global())
            .sink { () in
                DataProvider.shared().bg.perform {
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
            .sink { () in
                L.importing.debug("🏎️🏎️ importEvents() after relay message received (throttle = 0.5 seconds), but sends first after debounce (0.15)")
                self.importEvents()
            }
            .store(in: &subscriptions)
        
        addedPrioRelayMessage
            .debounce(for: .seconds(0.05), scheduler: DispatchQueue.global())
            .throttle(for: 0.25, scheduler: DispatchQueue.global(), latest: true)
            .receive(on: DispatchQueue.global())
            .sink { () in
                L.importing.debug("🏎️🏎️ importEvents() after relay message received (throttle = 0.25 seconds), but sends first after debounce (0.05)")
                self.importPrioEvents()
            }
            .store(in: &subscriptions)
    }
    
    
    // Load all kind 3 ids, these are expensive to parse
    // and load recent 5000
    // Might as well just load all??? Its fast anyway
    func preloadExistingIdsCache() {
        let fr = Event.fetchRequest()
        fr.fetchLimit = 1_000_000
//        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.propertiesToFetch = ["id", "relays"]
        DataProvider.shared().bg.performAndWait { [unowned self] in // AndWait because existingIds MUST be in sync with db
            if let results = try? DataProvider.shared().bg.fetch(fr) {
                self.existingIds = results.reduce(into: [String: EventState]()) { (dict, event) in
                    dict[event.id] = EventState(status: .SAVED, relays: event.relays)
                }
                L.og.debug("\(self.existingIds.count) existing ids added to cache")
            }
        }
    }
    
    public func importEvents() {
        let context = DataProvider.shared().bg
        context.perform { [unowned self] in
            if (self.isImporting) {
                let itemsCount = MessageParser.shared.messageBucket.count
                self.needsImport = true
                if itemsCount > 0 {
                    DispatchQueue.main.async {
                        sendNotification(.listStatus, "Processing \(itemsCount) items...")
                    }
                }
                return
            }
            
            if (self.isImportingPrio) {
//                let itemsCount = MessageParser.shared.messageBucket.count
                self.needsImport = true
//                if itemsCount > 0 {
//                    DispatchQueue.main.async {
//                        sendNotification(.listStatus, "Processing \(itemsCount) items...")
//                    }
//                }
                return
            }
            
            self.isImporting = true
            let forImportsCount = MessageParser.shared.messageBucket.count
            guard forImportsCount != 0 else {
                L.importing.debug("🏎️🏎️ importEvents() nothing to import.")
                self.isImporting = false; return }
            
            DispatchQueue.main.async {
                sendNotification(.listStatus, "Processing \(forImportsCount) items...")
            }
            
            do {
                var count = 0
                var alreadyInDBskipped = 0
                var saved = 0
                
                // We send a notification every .save with the saved subscriptionIds
                // so other parts of the system can start fetching from local db
                var subscriptionIds = Set<String>()
                while let message = MessageParser.shared.messageBucket.popFirst() {
                    count = count + 1
                    guard var event = message.event else {
                        L.importing.error("🔴🔴 message.event is nil \(message.message)")
                        continue
                    }
                    
                    if (MessageParser.shared.isSignatureVerificationEnabled) {
                        guard try event.verified() else {
                            L.importing.info("🔴🔴😡😡 hey invalid sig yo 😡😡")
                            continue
                        }
                    }
                    
                    if event.kind == .nwcInfo {
                        _ = existingIds.removeValue(forKey: event.id)
                        guard let nwcConnection = self.nwcConnection else { continue }
                        guard event.publicKey == nwcConnection.walletPubkey else { continue }
                        L.og.info("⚡️ Received 13194 info event, saving methods: \(event.content)")
                        nwcConnection.methods = event.content
                        DispatchQueue.main.async {
                            sendNotification(.nwcInfoReceived, NWCInfoNotification(methods: event.content))
                        }
                        continue
                    }
                    
                    if message.subscriptionId == "Notifications" && event.pTags().contains(NRState.shared.activeAccountPublicKey) && [1,9802,30023,7,9735,4].contains(event.kind.id) {
                        NRState.shared.loggedInAccount?.lastNotificationReceivedAt = Date.now
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
                        Event.updateRelays(event.id, relays: message.relays)
                        var alreadySavedSubs = Set<String>()
                        if let subscriptionId = message.subscriptionId {
                            alreadySavedSubs.insert(subscriptionId)
                        }
                        self.importedMessagesFromSubscriptionIds.send(alreadySavedSubs)
                        continue
                    }
                    // Skip if we already have a newer kind 3
                    if  event.kind == .contactList,
                        let existingKind3 = Event.fetchReplacableEvent(3, pubkey: event.publicKey, context: context),
                        existingKind3.created_at > Int64(event.createdAt.timestamp)
                    {
                        if event.publicKey == NRState.shared.activeAccountPublicKey && event.kind == .contactList { // To enable Follow button we need to have received a contact list
                            DispatchQueue.main.async {
                                FollowingGuardian.shared.didReceiveContactListThisSession = true
                            }
                        }
                        continue
                    }
                    
                    var kind6firstQuote:Event?
                    if event.kind == .repost && (event.content.prefix(2) == #"{""# || event.content == "") {
                        if event.content == "" {
                            if let firstE = event.firstE() {
                                // TODO: Should be able to use existingIds here...
                                kind6firstQuote = try? Event.fetchEvent(id: firstE, context: context)
                            }
                        }
                        else if let noteInNote = try? decoder.decode(NEvent.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) {
                            if !Event.eventExists(id: noteInNote.id, context: context) { // TODO: check existingIds instead of .eventExists
                                kind6firstQuote = Event.saveEvent(event: noteInNote, relays: message.relays)
                                kind6firstQuote?.repostsCount = 1
                            }
                            else {
                                Event.updateRelays(noteInNote.id, relays: message.relays)
                            }
                            event.content = "#[0]"
                            event.tags.insert(NostrTag(["e", noteInNote.id, "", "mention"]), at: 0)
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
                    
                    let savedEvent = Event.saveEvent(event: event, relays: message.relays, kind6firstQuote:kind6firstQuote)
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
                        do { try _ = Event.updateLikeCountCache(savedEvent, content:event.content, context: context) } catch {
                            L.importing.error("🦋🦋🔴🔴🔴 problem updating Like Count Cache .id \(event.id)")
                        }
                    }
//                    if event.kind == .repost {
//                        do { try _ = Event.updateRepostCountCache(savedEvent, content:event.content, context: context) } catch {
//                            L.importing.error("🦋🦋🔴🔴🔴 problem updating Repost Count Cache .id \(event.id)")
//                        }
//                    }
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                    if event.kind == .zapNote {
                        let _ = Event.updateZapTallyCache(savedEvent, context: context)
                    }
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REPLIES, MENTIONS)
                    if event.kind == .textNote || event.kind == .repost {
                        // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
                        do { try _ = Event.updateMentionsCountCache(event.tags, context: context) } catch {
                            L.importing.error("🦋🦋🔴🔴🔴 problem updateMentionsCountCache .id \(event.id)")
                        }
                        
                        // NIP-10: Those marked with "reply" denote the id of the reply event being responded to.
                        // NIP-10: Those marked with "root" denote the root id of the reply thread being responded to.
                        // DISABLED BECAUSE ALREADY DONE IN saveEvent.
                        //                        do { try _ = Event.updateRepliesCountCache(event.tags, context: context) } catch {
                        //                            print("🦋🦋🔴🔴🔴 problem updateRepliesCountCache .id \(event.id)")
                        //                        }
                    }
                    
                    // batch save every 100
                    if count % 100 == 0 {
                        if (context.hasChanges) {
                            do {
                                try context.save()
                                L.importing.info("💾💾 Saved \(count)/\(forImportsCount)")
                                let mainQueueCount = count
                                let mainQueueForImportsCount = forImportsCount
                                self.importedMessagesFromSubscriptionIds.send(subscriptionIds)
                                DispatchQueue.main.async {
                                    sendNotification(.listStatus, "Processing \(mainQueueCount)/\(max(mainQueueCount,mainQueueForImportsCount)) items...")
                                    sendNotification(.newEventsInDatabase)
                                }
                                subscriptionIds.removeAll()
                            }
                            catch {
                                L.importing.error("🏎️🏎️ 🔴🔴🔴 Error on batch \(count)/\(forImportsCount): \(error)")
                            }
                        }
                    }
                }
                if (context.hasChanges) {
                    try context.save() // This is saving bg context to main, not to disk
                    if (saved > 0) {
                        L.importing.info("💾💾 Processed: \(forImportsCount), saved: \(saved), skipped (db): \(alreadyInDBskipped)")
                        let mainQueueCount = count
                        let mainQueueForImportsCount = forImportsCount
                        self.importedMessagesFromSubscriptionIds.send(subscriptionIds)
                        DispatchQueue.main.async {
                            sendNotification(.listStatus, "Processing \(mainQueueCount)/\(max(mainQueueCount,mainQueueForImportsCount)) items...")
                            sendNotification(.newEventsInDatabase)
                        }
                        subscriptionIds.removeAll()
                    }
                    else {
                        L.importing.info("💾   Finished, nothing saved. -- Processed: \(forImportsCount), saved: \(saved), skipped (db): \(alreadyInDBskipped)")
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
                DataProvider.shared().save()
            }
        }
    }
    
    public func importPrioEvents() {
        let context = DataProvider.shared().bg
        context.perform { [unowned self] in
            let forImportsCount = MessageParser.shared.priorityBucket.count
            guard forImportsCount != 0 else {
                L.importing.debug("🏎️🏎️ importPrioEvents() nothing to import.")
                return
            }
            
            DispatchQueue.main.async {
                sendNotification(.listStatus, "Processing \(forImportsCount) items...")
            }
            
            do {
                var count = 0
                var alreadyInDBskipped = 0
                var saved = 0
                
                while let message = MessageParser.shared.priorityBucket.popFirst() {
                    count = count + 1
                    guard var event = message.event else {
                        L.importing.error("🔴🔴 message.event is nil \(message.message)")
                        continue
                    }
                    
                    if (MessageParser.shared.isSignatureVerificationEnabled) {
                        guard try event.verified() else {
                            L.importing.info("🔴🔴😡😡 hey invalid sig yo 😡😡")
                            continue
                        }
                    }
                    
                    if event.kind == .nwcInfo {
                        _ = existingIds.removeValue(forKey: event.id)
                        guard let nwcConnection = self.nwcConnection else { continue }
                        guard event.publicKey == nwcConnection.walletPubkey else { continue }
                        L.og.info("⚡️ Received 13194 info event, saving methods: \(event.content)")
                        nwcConnection.methods = event.content
                        DispatchQueue.main.async {
                            sendNotification(.nwcInfoReceived, NWCInfoNotification(methods: event.content))
                        }
                        continue
                    }
                                         
                    guard existingIds[event.id]?.status != .SAVED else {
                        alreadyInDBskipped = alreadyInDBskipped + 1
                        if event.publicKey == NRState.shared.activeAccountPublicKey && event.kind == .contactList { // To enable Follow button we need to have received a contact list
                            DispatchQueue.main.async {
                                FollowingGuardian.shared.didReceiveContactListThisSession = true
                            }
                        }
                        Event.updateRelays(event.id, relays: message.relays)
                        if let subscriptionId = message.subscriptionId, let savedEvent = try? Event.fetchEvent(id: event.id, context: context) {
                            let importedNotification = ImportedPrioNotification(subscriptionId: subscriptionId, event: savedEvent)
                            DispatchQueue.main.async {
                                sendNotification(.importedPrioMessage, importedNotification)
                            }
                        }
                        continue
                    }
                    // Skip if we already have a newer kind 3
                    if  event.kind == .contactList,
                        let existingKind3 = Event.fetchReplacableEvent(3, pubkey: event.publicKey, context: context),
                        existingKind3.created_at > Int64(event.createdAt.timestamp)
                    {
                        if event.publicKey == NRState.shared.activeAccountPublicKey && event.kind == .contactList { // To enable Follow button we need to have received a contact list
                            DispatchQueue.main.async {
                                FollowingGuardian.shared.didReceiveContactListThisSession = true
                            }
                        }
                        continue
                    }
                    
                    var kind6firstQuote:Event?
                    if event.kind == .repost && (event.content.prefix(2) == #"{""# || event.content == "") {
                        if event.content == "" {
                            if let firstE = event.firstE() {
                                // TODO: Should be able to use existingIds here...
                                kind6firstQuote = try? Event.fetchEvent(id: firstE, context: context)
                            }
                        }
                        else if let noteInNote = try? decoder.decode(NEvent.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) {
                            if !Event.eventExists(id: noteInNote.id, context: context) { // TODO: check existingIds instead of .eventExists
                                kind6firstQuote = Event.saveEvent(event: noteInNote, relays: message.relays)
                                kind6firstQuote?.repostsCount = 1
                            }
                            else {
                                Event.updateRelays(noteInNote.id, relays: message.relays)
                            }
                            event.content = "#[0]"
                            event.tags.insert(NostrTag(["e", noteInNote.id, "", "mention"]), at: 0)
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
                    
                    let savedEvent = Event.saveEvent(event: event, relays: message.relays, kind6firstQuote:kind6firstQuote)
                    saved = saved + 1
                    
                    
                    if let subscriptionId = message.subscriptionId {
                        let importedNotification = ImportedPrioNotification(subscriptionId: subscriptionId, event: savedEvent)
                        DispatchQueue.main.async {
                            sendNotification(.importedPrioMessage, importedNotification)
                        }
                    }
                    if (kind6firstQuote != nil) {
                        savedEvent.firstQuote = kind6firstQuote
                    }
                    
                    if event.kind == .setMetadata {
                        Contact.saveOrUpdateContact(event: event)
                    }
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                    if event.kind == .reaction {
                        do { try _ = Event.updateLikeCountCache(savedEvent, content:event.content, context: context) } catch {
                            L.importing.error("🦋🦋🔴🔴🔴 problem updating Like Count Cache .id \(event.id)")
                        }
                    }
//                    if event.kind == .repost {
//                        do { try _ = Event.updateRepostCountCache(savedEvent, content:event.content, context: context) } catch {
//                            L.importing.error("🦋🦋🔴🔴🔴 problem updating Repost Count Cache .id \(event.id)")
//                        }
//                    }
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                    if event.kind == .zapNote {
                        let _ = Event.updateZapTallyCache(savedEvent, context: context)
                    }
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REPLIES, MENTIONS)
                    if event.kind == .textNote || event.kind == .repost {
                        // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
                        do { try _ = Event.updateMentionsCountCache(event.tags, context: context) } catch {
                            L.importing.error("🦋🦋🔴🔴🔴 problem updateMentionsCountCache .id \(event.id)")
                        }
                        
                        // NIP-10: Those marked with "reply" denote the id of the reply event being responded to.
                        // NIP-10: Those marked with "root" denote the root id of the reply thread being responded to.
                        // DISABLED BECAUSE ALREADY DONE IN saveEvent.
                        //                        do { try _ = Event.updateRepliesCountCache(event.tags, context: context) } catch {
                        //                            print("🦋🦋🔴🔴🔴 problem updateRepliesCountCache .id \(event.id)")
                        //                        }
                    }
                }
                if (context.hasChanges) {
                    try context.save() // This is saving bg context to main, not to disk
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
