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
                    let event = message.event!
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
                    
                    _ = Event.saveEvent(event: event, context:context)
                    
                    if event.kind == .setMetadata {
                        if Contact.handleSetMetadataEvent(event: event, context: context) != nil {
                            
                        }
                    }
                    
                    if event.kind == .custom(3) {
                        print("kind 3 event \(event.id) saved, but no further handling done yet...")
                    }
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                    if event.kind == .custom(7) {
                        do { try _ = Event.updateLikeCountCache(event.tags, content:event.content, context: context) } catch {
                            print("🦋🦋🔴🔴🔴 problem updating Like Count Cache .id \(event.id)")
                        }
                    }
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REPLIES, MENTIONS)
                    if event.kind == .textNote {
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
