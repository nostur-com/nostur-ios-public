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
    var settingsStore = SettingsStore.shared
    var isImporting = false
    
    static var shared = Importer()
    
    var lastTimelineEventTimestamp:NTimestamp? = nil
    
    public func importEvents() async {
        if (isImporting) {
            print("🟠🟠🟠 ALREADY IMPORTING. SKIPPED 🟠🟠🟠")
            return
        }
        let ot = OnboardingTracker.shared
        
        isImporting = true
        
        let parsedBucket = MessageParser.shared.parsedBucket
        guard await parsedBucket.count() != 0 else { self.isImporting = false; return }
        print("🦋🦋 \(await parsedBucket.count()) messages in parsedBucket.")
        
        var forImports = [RelayMessage]()
        while let forImport = await parsedBucket.dequeue() {
            forImports.append(forImport)
        }
        
        let isSignatureVerificationEnabled = self.settingsStore.isSignatureVerificationEnabled
        
//        context.performAndWait {
        await EventsProvider.shared.container.performBackgroundTask { context in
            
            var alreadyInLRUskipped = 0
            var alreadyInDBskipped = 0
            var saved = 0
            
            do {
                for message in forImports {
                    var event = message.event!
                    self.rememberTimestamp(event:event)
                    
                    guard SavedEventsCache.shared.retrieveObject(at: event.id) == nil else {
                        alreadyInLRUskipped = alreadyInLRUskipped + 1
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
                        if let noteInNote = try? decoder.decode(NEvent.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) {
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
                    
                    SavedEventsCache.shared.setObject(for: event.id, value: event.createdAt)
                }
                if (context.hasChanges) {
                    try context.save() // TODO: is this the slowdown??
                    if (saved > 0) {
                        print("💾 forImports: \(forImports.count), saved: \(saved), skipped (cache): \(alreadyInLRUskipped), skipped (db): \(alreadyInDBskipped)")
                    }
//                    DispatchQueue.main.async {
//                        sendNotification(.viewNeedsUpdate)
//                    }
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
    
    func rememberTimestamp(event: NEvent) {
        if event.kind == .textNote || event.kind == .custom(7) {
            // don't remember if timestamp is in the future
            if event.createdAt.timestamp > Int(Date().timeIntervalSince1970) {
                return
            }
            
            // remember timestamp if its the first one
            if (self.lastTimelineEventTimestamp == nil) {
                self.lastTimelineEventTimestamp = event.createdAt
            }
            else {
                // only remember if timestamp is newer than already remembered timestamp
                if (event.createdAt.timestamp > self.lastTimelineEventTimestamp!.timestamp) {
                    self.lastTimelineEventTimestamp = event.createdAt
                }
            }
        }
    }
}
