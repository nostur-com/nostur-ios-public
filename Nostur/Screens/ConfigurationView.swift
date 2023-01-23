//
//  ConfigurationView.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2023.
//

import SwiftUI
import CoreData

struct ConfigurationView: View {
    
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Contact.updated_at, order: .forward)],
        animation: .none)
    var allContacts: FetchedResults<Contact>
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Event.created_at, order: .forward)],
        animation: .none)
    var allEvents: FetchedResults<Event>
    
    func rebuildReplyToIdsCache() {
        let kind1 = allEvents.filter { $0.kind == 1 }
        
        let taskContext = EventsProvider.shared.container.newBackgroundContext()
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // Set unused undoManager to nil for macOS (it is nil by default on iOS)
        // to reduce resource requirements.
        taskContext.undoManager = nil
        // Add name and author to identify source of persistent history changes.
        taskContext.name = "rebuildReplyToIdsCacheContext"
        taskContext.transactionAuthor = "rebuildReplyToIdsCache"
        
        taskContext.performAndWait {
         
            
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
//                            event.replyToId = replyToEtag.id
//                            print("updating replyToId for \(String(describing: event.id))")
                        }
                        
                        if let replyToRootEtag = TagsHelpers(tags).replyToRootEtag() {
                            event.replyToRootId = replyToRootEtag.id
                            if (event.replyToId == nil) {
                                event.replyToId = replyToRootEtag.id
                            }
                            print("updating replyToRootId for \(String(describing: event.id))")
                        }
                        
                    }
                }
            }
            
            do {
                try taskContext.save()
            }
            catch {
                print(error)
            }
            
            try! viewContext.save()
        }
    }
    
    func rebuildCountingCache() {
        
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
            let firstEvent = allEvents.first
            print("first event: \(String(describing: firstEvent!.id)) date/time: \(Date(timeIntervalSince1970: TimeInterval(firstEvent!.created_at))) ")
            // for each event (KIND 1 or 7)
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
            
            
            print("Finishing up with viewContext.save()")
            
            do {
                try taskContext.save()
            }
            catch {
                print(error)
            }
        }
        try! viewContext.save()
    }
    
    func rebuildContactCache() {
        // sort events by date. oldest first
        
        
        // for each event (KIND 0) (SET METADATA)
        
        // update fields. BUT ALSO NIL THEM IF MISSING // TODO: SHOULD ALSO DO IN REGULAR METADATA PARSING
    }
    
    var body: some View {
        VStack {
            //            RelaysView()
            Divider()
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
            
            Text("\n")
            
            Button {
                rebuildContactCache()
            } label: {
                Text("Rebuild contact cache (banner, picture etc)")
            }.padding(10)
        }
    }
}

struct ConfigurationView_Previews: PreviewProvider {
    
    static var previewUserDefaults: UserDefaults = {
        let d = UserDefaults(suiteName: "preview_user_defaults")!
        
        d.set("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", forKey: "activeAccountPublicKey")
        
        return d
    }()
    
    static var previews: some View {
        
        let accountState = AccountState(viewContext: EventsProvider.preview.container.viewContext)
        
        let cm = ConnectionManager()
        
        ConfigurationView()
            .defaultAppStorage(previewUserDefaults)
            .environment(\.managedObjectContext,
                          EventsProvider.preview.container.viewContext)
            .environmentObject(accountState)
            .environmentObject(cm)
    }
}
