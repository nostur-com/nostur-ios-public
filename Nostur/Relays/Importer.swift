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
    var isImporting = false
    
    let logger = Logger(subsystem: "com.nostir.2140.Events", category: "persistence")
    
    static var shared = Importer()
    
    var lastTimelineEventTimestamp:NTimestamp? = nil
    
    public func importEvents() async {
        if (isImporting) {
            print("🟠🟠🟠 ALREADY IMPORTING. SKIPPED 🟠🟠🟠")
            return
        }
        
        isImporting = true
        
        let parsedBucket = MessageParser.shared.parsedBucket
        guard await parsedBucket.count() != 0 else { self.isImporting = false; return }
        print("🦋🦋 \(await parsedBucket.count()) messages in parsedBucket.")
        
        var forImports = [RelayMessage]()
        while let forImport = await parsedBucket.dequeue() {
            forImports.append(forImport)
        }
        
        let context = EventsProvider.shared.container.newBackgroundContext()
        
        await context.perform {
            
            var alreadyInLRUskipped = 0
            var alreadyInDBskipped = 0
            
            do {
                for message in forImports {
                    var event = message.event!
                    self.rememberTimestamp(event:event)
                    
                    guard SavedEventsCache.shared.retrieveObject(at: event.id) == nil else {
                        alreadyInLRUskipped = alreadyInLRUskipped + 1
                        continue
                    }
                    
                    guard try Event.fetchEvent(id: event.id, context: context) == nil else {
                        alreadyInDBskipped = alreadyInDBskipped + 1
                        continue
                    }
                    
                    guard try event.verified() else {
                        print("😡😡 hey invalid sig yo 😡😡")
                        continue
                    }
                    
                    if event.kind == .setMetadata { // What's best? Delete existing kind 3, then insert? Mark existing deletedAt, then insert? Or just update existing event?
                        // for now, delete older and hope the new insert never fails
                        let r = NSFetchRequest<Event>(entityName: "Event")
                        r.predicate = NSPredicate(format: "kind == 3 AND pubkey == %@ AND created_at < %i", event.publicKey, event.createdAt.timestamp)
                        let olderKind3 = try! context.fetch(r)
                        for older in olderKind3 {
                            context.delete(older)
                        }
                    }
                    
                    // ANNOYING FIX FOR KIND 6 WITH JSON STRING OF ANOTHER EVENT IN EVENT.CONTENT. WTF
                    if event.kind == .repost && event.content.prefix(2) == #"{""# {
                        let decoder = JSONDecoder()
                        if let noteInNote = try? decoder.decode(NEvent.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) {
                            _ = Event.saveEvent(event: noteInNote, context:context)
                            event.content = "#[0]"
                            event.tags.insert(NEventTag(type: "e", otherInformation: noteInNote.id, "", "mention"), at: 0)
                        }
                    }
                    
                    let savedEvent = Event.saveEvent(event: event, context:context)
                    
                    if event.kind == .setMetadata {
                        Contact.saveOrUpdateContact(event: event, context: context)
                        Account.preFillReadOnlyAccountInfo(event: event, context: context)
                    }
                    
                    if event.kind == .contactList {
                        Account.preFillReadOnlyAccountFollowing(event: event, context: context)
                    }
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                    if event.kind == .reaction {
                        do { try _ = Event.updateLikeCountCache(event.tags, content:event.content, context: context) } catch {
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
                        do { try _ = Event.updateRepliesCountCache(event.tags, context: context) } catch {
                            print("🦋🦋🔴🔴🔴 problem updateRepliesCountCache .id \(event.id)")
                        }
                    }
                    
                    SavedEventsCache.shared.setObject(for: event.id, value: event.createdAt)
                }
                
                if (alreadyInLRUskipped > 0) {
                    print("🦋🦋 Skipped \(alreadyInLRUskipped) already in LRU cache")
                }
                if (alreadyInDBskipped > 0) {
                    print("🦋🦋 Skipped \(alreadyInDBskipped) already in DB")
                }
                
                //                ThreadWarning.which("importEvents")
                if (context.hasChanges) {
                    try context.save() // TODO: is this the slowdown??
                    
                    //                    print("✅✅✅ context.save() ✅✅✅")
                }
                
                //                self.logger.debug("Successfully inserted data.")
                self.isImporting = false
            }
            catch {
                self.isImporting = false
                print("🦋🦋 we failed to import because:")
                print("🦋🦋 \(error)")
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
