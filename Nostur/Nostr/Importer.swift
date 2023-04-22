//
//  Importer.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/01/2023.
//

import Foundation
import OSLog
import CoreData

class Importer {
    var queue = DispatchQueue(label: "com.nostur.importer")
    var settingsStore = SettingsStore.shared
    private var _isImporting = false
    
    var isImporting: Bool {
        get {
            return queue.sync {
                _isImporting
            }
        }
        set {
            queue.sync {
                _isImporting = newValue
            }
        }
    }
    
    var existingIds:Set<String> = []
    
    static let shared = Importer()
    
    init() {
        self.preloadExistingIdsCache()
        print("\(existingIds.count) existing ids in cache")
    }
    
    func preloadExistingIdsCache() {
        let fr = Event.fetchRequest()
        fr.fetchLimit = 3000
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.propertiesToFetch = ["id"]
        if let results = try? DataProvider.shared().viewContext.fetch(fr) {
            self.existingIds = Set(results.map { $0.id })
        }
    }
    
    public func importEvents() async {
        let parsedBucket = MessageParser.shared.parsedBucket
        if (isImporting) {
            let itemsCount = await parsedBucket.count()
            print("🟠🟠🟠 ALREADY IMPORTING. SKIPPED importEvents with \(itemsCount) in bucket 🟠🟠🟠")
            if itemsCount > 0 {
                DispatchQueue.main.async {
                    sendNotification(.listStatus, "Processing \(itemsCount) items...")
                }
            }
            return
        }
        let ot = OnboardingTracker.shared
        
        isImporting = true
        
        let itemsCount = await parsedBucket.count()
        guard itemsCount != 0 else { self.isImporting = false; return }
//        print("🦋🦋 \(itemsCount) messages in parsedBucket.")
        //        if itemsCount == 1 {
        //            print(await parsedBucket.all().description)
        //        }
        DispatchQueue.main.async {
            sendNotification(.listStatus, "Processing \(itemsCount) items...")
        }
        
        var forImports = [RelayMessage]()
        while let forImport = await parsedBucket.dequeue() {
            forImports.append(forImport)
        }
        
        let isSignatureVerificationEnabled = self.settingsStore.isSignatureVerificationEnabled
        
        //        context.performAndWait {
        await EventsProvider.shared.container.performBackgroundTask { context in
            
            var alreadyInIdCacheSkipped = 0
            var alreadyInDBskipped = 0
            var saved = 0
            
            do {
                for message in forImports {
                    var event = message.event!
                    
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
                            print("😡😡 hey invalid sig yo 😡😡")
                            continue
                        }
                    }
                    
                    // ANNOYING FIX FOR KIND 6 WITH JSON STRING OF ANOTHER EVENT IN EVENT.CONTENT. WTF
                    var kind6firstQuote:Event?
                    if event.kind == .repost && (event.content.prefix(2) == #"{""# || event.content == "") {
                        let decoder = JSONDecoder()
                        if event.content == "" {
                            if let firstE = event.firstE() {
                                kind6firstQuote = try? Event.fetchEvent(id: firstE, context: context)
                            }
                        }
                        else if let noteInNote = try? decoder.decode(NEvent.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) {
                            if !Event.eventExists(id: noteInNote.id, context: context) {
                                _ = Event.saveEvent(event: noteInNote, context:context)
                            }
                            else {
                                //                                print("🔴 noteInNote already in db")
                            }
                            event.content = "#[0]"
                            event.tags.insert(NEventTag(type: "e", otherInformation: noteInNote.id, "", "mention"), at: 0)
                        }
                    }
                    
                    if event.kind == .contactList {
                        if event.publicKey == NosturState.EXPLORER_PUBKEY {
                            // use guest account p's for "Explorer" feed
                            // TODO: Need objectWillChange.send() here or not?
                            let pTags = event.pTags()
                            Task { @MainActor in
                                //                                NosturState.shared.objectWillChange.send()
                                NosturState.shared.rawExplorePubkeys = Set(pTags)
                            }
                        }
                        
                        if (ot.isOnboarding && ot.pubkey == event.publicKey) { // TODO: skip if first time completed
                            print("🟠🟠🟠 3")
                            ot.didFetchKind3 = true
                            ot.followingKeys = event.pTags()
                            print("✈️✈️✈️ ONBORADING SPEED UP FETCHING P's FROM 3")
                            let fetchPs = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: event.pTags()))
                            SocketPool.shared.sendMessage(fetchPs)
                            
                            print("✈️✈️✈️ ONBORADING SPEED UP FETCHING 0,1,6 FROM P's")
                            let fetchTimeline = ClientMessage(type: .REQ, message: RequestMessage.getFollowingEvents(pubkeys: event.pTags()))
                            
                            SocketPool.shared.sendMessage(fetchTimeline)
                            //                            print("✈️✈️✈️ ONBORADING SPEED UP FETCHING 1,6,7,9735 FROM E's")
                            //                            let fetchReferences = ClientMessage(type: .REQ, message: RequestMessage.getEventReferences(ids: ????))
                            Account.preFillReadOnlyAccountFollowing(event: event, context: context, forceOverwrite: true)
                        }
                        
                        let n = event
                        DispatchQueue.main.async {
                            sendNotification(.newFollowingListFromRelay, n)
                        }
                    }
                    
                    let savedEvent = Event.saveEvent(event: event, context:context, relay: message.relay)
                    saved = saved + 1
                    if (kind6firstQuote != nil) {
                        savedEvent.firstQuote = kind6firstQuote
                    }
                    
                    if event.kind == .setMetadata {
                        Contact.saveOrUpdateContact(event: event, context: context)
                        if (ot.isOnboarding && ot.pubkey == event.publicKey) {
                            print("🟠🟠🟠 2")
                            Account.preFillReadOnlyAccountInfo(event: event, context: context, forceOverwrite: true)
                            ot.didFetchKind0 = true
                        }
                    }
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                    if event.kind == .reaction {
                        do { try _ = Event.updateLikeCountCache(savedEvent, content:event.content, context: context) } catch {
                            print("🦋🦋🔴🔴🔴 problem updating Like Count Cache .id \(event.id)")
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
                            print("🦋🦋🔴🔴🔴 problem updateMentionsCountCache .id \(event.id)")
                        }
                        
                        // NIP-10: Those marked with "reply" denote the id of the reply event being responded to.
                        // NIP-10: Those marked with "root" denote the root id of the reply thread being responded to.
                        // DISABLED BECAUSE ALREADY DONE IN saveEvent.
                        //                        do { try _ = Event.updateRepliesCountCache(event.tags, context: context) } catch {
                        //                            print("🦋🦋🔴🔴🔴 problem updateRepliesCountCache .id \(event.id)")
                        //                        }
                    }
                    
                    self.existingIds.insert(event.id)
                }
                if (context.hasChanges) {
                    try context.save() // TODO: is this the slowdown??
                    if (saved > 0) {
                        print("💾 Processed: \(forImports.count), saved: \(saved), skipped (new cache): \(alreadyInIdCacheSkipped), skipped (db): \(alreadyInDBskipped)")
                    }
                }
                self.isImporting = false
            }
            catch {
                self.isImporting = false
                print("🔴🔴🔴🔴🔴🔴 Failed to import because:")
                print("🔴🔴🔴🔴🔴🔴 \(error)")
            }
        }
    }
}
