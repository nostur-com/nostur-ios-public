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

class Importer {
    
    var isImporting = false
    var needsImport = false
    var subscriptions = Set<AnyCancellable>()
    var addedRelayMessage = PassthroughSubject<Void, Never>()

    var settingsStore = SettingsStore.shared
    
    var existingIds:Set<String> = []
    
    static let shared = Importer()
    
    let decoder = JSONDecoder()
    
    init() {
        self.preloadExistingIdsCache()
        triggerImportWhenRelayMessagesAreAdded()
    }
    
    func triggerImportWhenRelayMessagesAreAdded() {
        addedRelayMessage
            .throttle(for: 1.5, scheduler: DispatchQueue.global(), latest: true)
//            .debounce(for: .seconds(0.1), scheduler: DispatchQueue.global())
            .sink { () in
//                print("🏎️🏎️ \(Date.now) Import requested, 1.5 sec after new relay message(s)")
//                print("🏎️🏎️ \(Date.now) Import requested, 0.1 after last debounce of new relay message(s)")
                L.importing.debug("🏎️🏎️ importEvents() after relay message received (throttled 1.5 seconds)")
                self.importEvents()
            }
            .store(in: &subscriptions)
    }
    
    func preloadExistingIdsCache() {
        let fr = Event.fetchRequest()
        fr.fetchLimit = 5000
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.propertiesToFetch = ["id"]
        DataProvider.shared().bg.perform { [unowned self] in
            if let results = try? DataProvider.shared().bg.fetch(fr) {
                self.existingIds = Set(results.map { $0.id })
//                print("\(self.existingIds.count) existing ids added to cache")
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
            self.isImporting = true
            let forImportsCount = MessageParser.shared.messageBucket.count
            guard forImportsCount != 0 else {
                L.importing.info("🏎️🏎️ importEvents() nothing to import.")
                self.isImporting = false; return }
            
            DispatchQueue.main.async {
                sendNotification(.listStatus, "Processing \(forImportsCount) items...")
            }
            
            let isSignatureVerificationEnabled = self.settingsStore.isSignatureVerificationEnabled
            
            do {
                var count = 0
                var alreadyInIdCacheSkipped = 0
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
                    
                    if message.subscriptionId == "Notifications" && event.pTags().contains(NosturState.shared.activeAccountPublicKey) && [1,7,9735,4].contains(event.kind.id) {
                        NosturState.shared.lastNotificationReceivedAt = Date.now
                    }
                    
                    if message.subscriptionId == "Profiles" && event.kind == .setMetadata {
                        NosturState.shared.lastProfileReceivedAt = Date.now
                    }
                    
                    guard !self.existingIds.contains(event.id) else {
                        alreadyInIdCacheSkipped = alreadyInIdCacheSkipped + 1
                        continue
                    }
                    
                    guard Event.eventExists(id: event.id, context: context) == false else {
                        alreadyInDBskipped = alreadyInDBskipped + 1
                        continue
                    }
                    
                    if (isSignatureVerificationEnabled) {
                        guard try event.verified() else {
                            L.importing.info("😡😡 hey invalid sig yo 😡😡")
                            continue
                        }
                    }
                    
                    // ANNOYING FIX FOR KIND 6 WITH JSON STRING OF ANOTHER EVENT IN EVENT.CONTENT. WTF
                    var kind6firstQuote:Event?
                    if event.kind == .repost && (event.content.prefix(2) == #"{""# || event.content == "") {
                        if event.content == "" {
                            if let firstE = event.firstE() {
                                kind6firstQuote = try? Event.fetchEvent(id: firstE, context: context)
                            }
                        }
                        else if let noteInNote = try? decoder.decode(NEvent.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) {
                            if !Event.eventExists(id: noteInNote.id, context: context) {
                                _ = Event.saveEvent(event: noteInNote)
                            }
                            else {
                                //                                print("🔴 noteInNote already in db")
                            }
                            event.content = "#[0]"
                            event.tags.insert(NostrTag(["e", noteInNote.id, "", "mention"]), at: 0)
                        }
                    }
                    
                    if event.kind == .contactList {
                        if event.publicKey == NosturState.EXPLORER_PUBKEY {
                            // use guest account p's for "Explorer" feed
                            let pTags = event.pTags()
                            Task { @MainActor in
                                NosturState.shared.rawExplorePubkeys = Set(pTags)
                            }
                        }

                        let n = event
                        DispatchQueue.main.async {
                            sendNotification(.newFollowingListFromRelay, n)
                        }
                    }
                    
                    let savedEvent = Event.saveEvent(event: event, relay: message.relay)
//                    last = savedEvent
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
                    
                    self.existingIds.insert(event.id)
                    
                    // batch save every 100
                    if count % 100 == 0 {
                        if (context.hasChanges) {
                            do {
                                try context.save()
                                L.importing.info("🏎️🏎️ \(Date.now) 💾 Saved \(count)/\(forImportsCount)")
                                let mainQueueCount = count
                                let mainQueueForImportsCount = forImportsCount
                                let importedNotification = ImportedNotification(subscriptionIds: subscriptionIds)
                                DispatchQueue.main.async {
                                    sendNotification(.importedMessagesFromSubscriptionIds, importedNotification)
                                    sendNotification(.listStatus, "Processing \(mainQueueCount)/\(max(mainQueueCount,mainQueueForImportsCount)) items...")
                                    sendNotification(.newEventsInDatabase)
                                }
                                subscriptionIds.removeAll()
                            }
                            catch {
                                L.importing.error("🏎️🏎️ \(Date.now) 🔴🔴🔴 Error on batch \(count)/\(forImportsCount): \(error)")
                            }
                        }
                    }
                }
                if (context.hasChanges) {
                    try context.save() // This is saving bg context to main, not to disk
                    if (saved > 0) {
                        L.importing.info("🏎️🏎️ \(Date.now) 💾 Processed: \(forImportsCount), saved: \(saved), skipped (new cache): \(alreadyInIdCacheSkipped), skipped (db): \(alreadyInDBskipped)")
                        let mainQueueCount = count
                        let mainQueueForImportsCount = forImportsCount
                        let importedNotification = ImportedNotification(subscriptionIds: subscriptionIds)
                        DispatchQueue.main.async {
                            sendNotification(.importedMessagesFromSubscriptionIds, importedNotification)
                            sendNotification(.listStatus, "Processing \(mainQueueCount)/\(max(mainQueueCount,mainQueueForImportsCount)) items...")
                            sendNotification(.newEventsInDatabase)
                        }
                        subscriptionIds.removeAll()
//                        if saved == 1, let last {
//                            print("Saved: \(last.toNEvent().eventJson())")
//                        }
                    }
                    else {
                        L.importing.info("🏎️🏎️ \(Date.now) 💾 Finished, nothing saved. -- Processed: \(forImportsCount), saved: \(saved), skipped (new cache): \(alreadyInIdCacheSkipped), skipped (db): \(alreadyInDBskipped)")
                    }
                }
                else {
                    L.importing.info("🏎️🏎️ Nothing imported, no changes in \(count) messages")
                    sendNotification(.noNewEventsInDatabase)
                }
            }
            catch {
                L.importing.error("🏎️🏎️🔴🔴🔴🔴 Failed to import because: \(error)")
            }
            self.isImporting = false
            if (self.needsImport) {
                L.importing.info("🏎️🏎️ Chaining next import ")
                self.needsImport = false
                self.importEvents()
            }
            else {
                DataProvider.shared().save()
            }
        }
    }
}
