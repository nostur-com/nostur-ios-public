//
//  ConfigurationView.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2023.
//

import SwiftUI
import CoreData

struct ConfigurationView: View {
    
    @AppStorage("devToggle") var devToggle: Bool = false
//    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Contact.updated_at, order: .forward)],
        animation: .none)
    var allContacts: FetchedResults<Contact>
    
//    @FetchRequest(
//        sortDescriptors: [SortDescriptor(\Event.created_at, order: .forward)],
//        animation: .none)
//    var allEvents: FetchedResults<Event>
    
    func rebuildReplyToIdsCache() {
        SavedEventsCache.shared.clear()
        let taskContext = EventsProvider.shared.container.newBackgroundContext()
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // Set unused undoManager to nil for macOS (it is nil by default on iOS)
        // to reduce resource requirements.
        taskContext.undoManager = nil
        // Add name and author to identify source of persistent history changes.
        taskContext.name = "rebuildReplyToIdsCacheContext"
        taskContext.transactionAuthor = "rebuildReplyToIdsCache"
        
        taskContext.performAndWait {
         
            let r = NSFetchRequest<Event>(entityName: "Event")
            r.predicate = NSPredicate(format: "kind == 1")
            r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
            let kind1 = try! taskContext.fetch(r)
            
            // ON FIRST PASS RESET ALL TO NIL
            for event in kind1 {
                event.replyToId = nil
                event.replyToRootId = nil
            }
            
            let decoder = JSONDecoder()
            
            for event in kind1 {
                if (event.tagsSerialized != nil) {
                    if let tags = try? decoder.decode([NEventTag].self, from: Data(event.tagsSerialized!.utf8)) {
                        
                        if let replyToEtag = TagsHelpers(tags).replyToEtag() {
                            event.replyToId = replyToEtag.id
//                            print("updating replyToId for \(String(describing: event.id))")
                        }
                        
                        if let replyToRootEtag = TagsHelpers(tags).replyToRootEtag() {
                            event.replyToRootId = replyToRootEtag.id
                            if (event.replyToId == nil) {
                                event.replyToId = replyToRootEtag.id
                            }
//                            print("updating replyToRootId for \(String(describing: event.id))")
                        }
                        
                    }
                }
            }
            
            do {
//                try viewContext.save()
                try taskContext.save()
            }
            catch {
                print("rebuildReplyToIdsCache error on save(): \(error)")
            }
        }
    }
    
    func rebuildCountingCache() {
        SavedEventsCache.shared.clear()
        let taskContext = EventsProvider.shared.container.newBackgroundContext()
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // Set unused undoManager to nil for macOS (it is nil by default on iOS)
        // to reduce resource requirements.
        taskContext.undoManager = nil
        // Add name and author to identify source of persistent history changes.
        taskContext.name = "rebuildCountingCacheContext"
        taskContext.transactionAuthor = "rebuildCountingCache"
        
        taskContext.performAndWait {
            // sort events by date. oldest first
            let r = NSFetchRequest<Event>(entityName: "Event")
            r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
            let allEvents = try! taskContext.fetch(r)
            
            let kind1or7 = allEvents.filter { $0.kind == 1 || $0.kind == 7 }
            let kind1 = allEvents.filter { $0.kind == 1 }
            
            let decoder = JSONDecoder()
            
            // ON FIRST PASS RESET ALL COUNTERS TO 0 (FOR KIND 1)
            for event in kind1 {
                event.replies = 0
                event.mentions = 0
                event.likes = 0
            }
            
            // RECOUNT
            for event in kind1or7 {
                
                // if reply or replytoroot (and KIND 1)
                // update replies counter
                if (event.kind == 1 && event.tagsSerialized != nil) {
                    do {
                        if let tags = try? decoder.decode([NEventTag].self, from: Data(event.tagsSerialized!.utf8)) {
                            try Event.updateRepliesCountCache(tags, context: taskContext)
                        }
                    }
                    catch {
                        print("something wrong with updating replies cache")
                        print(error)
                    }
                }
                
                
                // if reaction (KIND 7)
                // update likes count
                if (event.kind == 7 && event.tagsSerialized != nil) {
                    do {
                        if let tags = try? decoder.decode([NEventTag].self, from: Data(event.tagsSerialized!.utf8)) {
                            try Event.updateLikeCountCache(tags, content:event.content ?? "", context: taskContext)
                        }
                    }
                    catch {
                        print("something wrong with updating likes/reactions cache")
                        print(error)
                    }
                }
                
                // if mentions (and KIND 1)
                // update mentions count
                if (event.kind == 1 && event.tagsSerialized != nil) {
                    do {
                        if let tags = try? decoder.decode([NEventTag].self, from: Data(event.tagsSerialized!.utf8)) {
                            try Event.updateMentionsCountCache(tags, context: taskContext)
                        }
                    }
                    catch {
                        print("something wrong with updating mentions cache")
                        print(error)
                    }
                }
            }
            
            
            print("Finishing up with taskContext.save()")

            do {
                try taskContext.save()
            }
            catch {
                print("rebuildCountingCache error on save(): \(error)")
                print(error)
            }
        }
    }
    
    func rebuildContactCache() {
        SavedEventsCache.shared.clear()
        // update fields. BUT ALSO NIL THEM IF MISSING // TODO: SHOULD ALSO DO IN REGULAR METADATA PARSING
        
        let taskContext = EventsProvider.shared.container.newBackgroundContext()
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // Set unused undoManager to nil for macOS (it is nil by default on iOS)
        // to reduce resource requirements.
        taskContext.undoManager = nil
        // Add name and author to identify source of persistent history changes.
        taskContext.name = "rebuildContactCacheContext"
        taskContext.transactionAuthor = "rebuildContactCache"
        
        taskContext.performAndWait {
         
            let decoder = JSONDecoder()
            
            let r = NSFetchRequest<Event>(entityName: "Event")
            r.predicate = NSPredicate(format: "kind == 0")
            r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)]
            let kind0 = try! taskContext.fetch(r)
            
            for event in kind0 {
                guard event.content != nil else {
                    continue
                }
            
                guard let metaData = try? decoder.decode(NSetMetadata.self, from: Data(event.content!.utf8)) else {
                    continue
                }
                
                do {
                    print("trying to update for \(String(describing: event.pubkey))")
                    try Contact.updateMetadata(metaData, pubkey: event.pubkey!, context: taskContext)
                }
                catch {
                    print("something wrong with updating conact info cache")
                    print(error)
                }
            }
            
            
            do {
                try taskContext.save()
            }
            catch {
                print("rebuildContactCache error on save(): \(error)")
                print(error)
            }
        }
    }
    
    func deleteAllContacts() {
        SavedEventsCache.shared.clear()
        let taskContext = EventsProvider.shared.container.newBackgroundContext()
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // Set unused undoManager to nil for macOS (it is nil by default on iOS)
        // to reduce resource requirements.
        taskContext.undoManager = nil
        // Add name and author to identify source of persistent history changes.
        taskContext.name = "deleteAllContactsContext"
        taskContext.transactionAuthor = "deleteAllContacts"
        
        taskContext.performAndWait {
         
            let r = NSFetchRequest<Contact>(entityName: "Contact")
            let allContacts = try! taskContext.fetch(r)
            
            for contact in allContacts {
                taskContext.delete(contact)
            }
            do {
                print("deleting \(allContacts.count) contacts.")
                try taskContext.save()
            }
            catch {
                print("deleteAllContacts error on save(): \(error)")
                print(error)
            }
        }
    }
    
    var body: some View {
        VStack {
            RelaysView()
            Divider()
            Toggle(isOn: $devToggle) {
                Text("Dev mode")
            }.padding(20)
            Divider()
            if (devToggle) {
                Group {
                    Text("Other options").font(.headline)
                    
                    Button {
                        rebuildReplyToIdsCache()
                    } label: {
                        Text("Rebuild replyToId, replyToRootId cache")
                    }.padding(10)
                    
                    Button {
                        rebuildCountingCache()
                    } label: {
                        Text("Rebuild counting cache (likes, mentions, replies)")
                    }.padding(10)
                    
                    Button {
                        rebuildContactCache()
                    } label: {
                        Text("Rebuild contact cache (banner, picture etc)")
                    }.padding(10)
                    
                    Button {
                        deleteAllContacts()
                    } label: {
                        Text("Delete all contacts \(allContacts.count)")
                    }.padding(10)
                    
                    Text("**Umb** [@snowder](nostr:npub1g53mukxnjkcmr94fhryzkqutdz2ukq4ks0gvy5af25rgmwsl4ngq43drvk)")
                    Text("**Umb** [@callebtc](nostr:npub12rv5lskctqxxs2c8rf2zlzc7xx3qpvzs3w4etgemauy9thegr43sf485vg)")
                    
                    Text("\n")
                }
            }
        }
    }
}

struct ConfigurationView_Previews: PreviewProvider {
    
    static var previews: some View {
    
        ConfigurationView()
            .withPreviewEnvironment()
    }
}
