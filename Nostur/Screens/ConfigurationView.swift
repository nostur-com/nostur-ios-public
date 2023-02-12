//
//  ConfigurationView.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2023.
//

import SwiftUI
import CoreData
//import Kingfisher

struct ConfigurationView: View {
    
    @AppStorage("devToggle") var devToggle: Bool = false
    @Environment(\.managedObjectContext) var viewContext

    @FetchRequest(fetchRequest: Contact.fetchRequest())
    var allContacts:FetchedResults<Contact>
    
    @FetchRequest(fetchRequest: Event.fetchRequest())
    var allEvents:FetchedResults<Event>
    
    @State var deleteAll = false
    @State var showDeleteAllEventsConfirmation = false
    @State var imageCacheSize = 0.0
    
    // Also fixes mention ids (first Quote Id)
    func rebuildReplyToIdsCache() {
        SavedEventsCache.shared.clear()
        
        
        let r = NSFetchRequest<Event>(entityName: "Event")
        r.predicate = NSPredicate(format: "kind == 1")
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        let kind1 = try! viewContext.fetch(r)
        
        // ON FIRST PASS RESET ALL TO NIL
        for event in kind1 {
            event.replyToId = nil
            event.replyToRootId = nil
            event.firstQuoteId = nil
        }
        
        let decoder = JSONDecoder()
        
        for event in kind1 {
            if (event.tagsSerialized != nil) {
                if let tags = try? decoder.decode([NEventTag].self, from: Data(event.tagsSerialized!.utf8)) {
                    
                    if let replyToEtag = TagsHelpers(tags).replyToEtag() {
                        event.replyToId = replyToEtag.id
                    }
                    
                    if let replyToRootEtag = TagsHelpers(tags).replyToRootEtag() {
                        event.replyToRootId = replyToRootEtag.id
                        if (event.replyToId == nil) {
                            event.replyToId = replyToRootEtag.id
                        }
                    }
                    
                    if let firstMentionEtag = TagsHelpers(tags).mentionEtags()?.first {
                        event.firstQuoteId = firstMentionEtag.id
                        if (event.firstQuoteId == nil) {
                            event.firstQuoteId = firstMentionEtag.id
                        }
                    }
                    
                }
            }
        }
        
        do {
            //                try viewContext.save()
            try viewContext.save()
        }
        catch {
            print("rebuildReplyToIdsCache error on save(): \(error)")
        }
        
    }
    
    func rebuildCountingCache() {
        SavedEventsCache.shared.clear()
        
        // sort events by date. oldest first
        let r = NSFetchRequest<Event>(entityName: "Event")
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        let allEvents = try! viewContext.fetch(r)
        
        let kind1or7 = allEvents.filter { $0.kind == 1 || $0.kind == 7 }
        let kind1 = allEvents.filter { $0.kind == 1 }
        
        let decoder = JSONDecoder()
        
        // ON FIRST PASS RESET ALL COUNTERS TO 0 (FOR KIND 1)
        for event in kind1 {
            event.repliesCount = 0 // TODO: Dit allemaal kan @aggregate worden?? @count ofzo?
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
                        try _ = Event.updateRepliesCountCache(tags, context: viewContext)
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
                        try _ = Event.updateLikeCountCache(tags, content:event.content ?? "", context: viewContext)
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
                        try _ = Event.updateMentionsCountCache(tags, context: viewContext)
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
            try viewContext.save()
        }
        catch {
            print("rebuildCountingCache error on save(): \(error)")
            print(error)
        }
        
    }
    
    func rebuildContactCache() {
        SavedEventsCache.shared.clear()
        // update fields. BUT ALSO NIL THEM IF MISSING // TODO: SHOULD ALSO DO IN REGULAR METADATA PARSING
        
        let decoder = JSONDecoder()
        
        let r = NSFetchRequest<Event>(entityName: "Event")
        r.predicate = NSPredicate(format: "kind == 0")
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)]
        let kind0 = try! viewContext.fetch(r)
        
        for event in kind0 {
            guard event.content != nil else {
                continue
            }
            
            guard let metaData = try? decoder.decode(NSetMetadata.self, from: Data(event.content!.utf8)) else {
                continue
            }
            
            do {
                print("trying to update for \(String(describing: event.pubkey))")
                try Contact.updateMetadata(metaData, pubkey: event.pubkey!, context: viewContext)
            }
            catch {
                print("something wrong with updating conact info cache")
                print(error)
            }
        }
        
        
        do {
            try viewContext.save()
        }
        catch {
            print("rebuildContactCache error on save(): \(error)")
            print(error)
        }
        
    }
    
    func deleteAllContacts() {
        SavedEventsCache.shared.clear()
        
        let r = NSFetchRequest<Contact>(entityName: "Contact")
        let allContacts = try! viewContext.fetch(r)
        
        for contact in allContacts {
            viewContext.delete(contact)
        }
        do {
            print("deleting \(allContacts.count) contacts.")
            try viewContext.save()
        }
        catch {
            print("deleteAllContacts error on save(): \(error)")
            print(error)
        }
    }
    
    func deleteAllEvents() {
        SavedEventsCache.shared.clear()
        
        let r = NSFetchRequest<Event>(entityName: "Event")
        let allEvents = try! viewContext.fetch(r)
        
        for event in allEvents {
            viewContext.delete(event)
        }
        do {
            print("deleting \(allEvents.count) contacts.")
            try viewContext.save()
        }
        catch {
            print("deleteAllEvents error on save(): \(error)")
            print(error)
        }
    }
    
    func fixContactEventRelations() {
        
        SavedEventsCache.shared.clear()
        
        
        // TODO: MAybe dont need for all events??? just kind:1 is enough?
        let er = NSFetchRequest<Event>(entityName: "Event")
        er.sortDescriptors = []
        let allEvents = Array(try! viewContext.fetch(er))
        
        
        for event in allEvents {
            // set relation to Contact
            let cr = NSFetchRequest<Contact>(entityName: "Contact")
            cr.predicate = NSPredicate(format: "pubkey == %@", event.pubkey!)
            cr.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
            if let contact = try? viewContext.fetch(cr).first {
                event.contact = contact
            }
        }
        
        do {
            print("Rebuilt event.contact relation")
            try viewContext.save()
        }
        catch {
            print("fixContactEventRelations error on save(): \(error)")
            print(error)
        }
        
    }
    
    func fixReplyToEventRelations() {
        
        SavedEventsCache.shared.clear()
        
        // TODO: MAybe dont need for all events??? just kind:1 is enough?
        let er = NSFetchRequest<Event>(entityName: "Event")
        er.sortDescriptors = []
        er.predicate = NSPredicate(format: "kind == 1")
        let allKind1 = Array(try! viewContext.fetch(er))
        
        for event in allKind1 {
            event.replyTo = nil
            event.replyToRoot = nil
            event.firstQuote = nil
            
            if (event.replyToId != nil) {
                let cr = NSFetchRequest<Event>(entityName: "Event")
                cr.predicate = NSPredicate(format: "id == %@", event.replyToId!)
                cr.sortDescriptors = []
                if let replyToEvent = try? viewContext.fetch(cr).first {
                    event.replyTo = replyToEvent
                    //                        replyToEvent.addToReplies(event) // TODO: inverse hoeft niet? automatisc?
                }
            }
            if (event.replyToRootId != nil) {
                let cr = NSFetchRequest<Event>(entityName: "Event")
                cr.predicate = NSPredicate(format: "id == %@", event.replyToRootId!)
                cr.sortDescriptors = []
                if let replyToRootEvent = try? viewContext.fetch(cr).first {
                    event.replyToRoot = replyToRootEvent
                }
            }
            
            if (event.firstQuoteId != nil) {
                let cr = NSFetchRequest<Event>(entityName: "Event")
                cr.predicate = NSPredicate(format: "id == %@", event.firstQuoteId!)
                cr.sortDescriptors = []
                if let mentionedEvent = try? viewContext.fetch(cr).first {
                    event.firstQuote = mentionedEvent
                }
            }
        }
        
        do {
            print("Rebuilt event.replyTo, event.replyToRoot, event.firstQuote relations")
            try viewContext.save()
        }
        catch {
            print("fixContactEventRelations error on save(): \(error)")
            print(error)
        }
        
    }
    
    func maintenance() {
        let frA = Account.fetchRequest()
        let allACcounts = Array(try! viewContext.fetch(frA))
        let ownAccountPubkeys = allACcounts.reduce([String]()) { partialResult, account in
            var newResult = Array(partialResult)
            newResult.append(account.publicKey!)
            return newResult
        }
        
        let ownAccountBookmarkIds = allACcounts.reduce([String]()) { partialResult, account in
            var newResult = Array(partialResult)
            if (account.bookmarks != nil) {
                let ids = account.bookmarks!.map { $0.id! }
                newResult.append(contentsOf: ids)
            }
            return newResult
        }
        
        let xDaysAgo = Date.now.addingTimeInterval(-3 * 86400) // 3 days
        
        
        // KIND 1 OF 7
        // OUDER DAN 3 DAGEN
        // IS GEEN BOOKMARK
        // IS GEEN EIGEN EVENT
        viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
            fetchRequest.predicate = NSPredicate(format: "(kind == 7 OR kind == 1) AND created_at < %i AND NOT id IN %@ AND NOT pubkey IN %@", Int64(xDaysAgo.timeIntervalSince1970), ownAccountBookmarkIds, ownAccountPubkeys)
            
            let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDelete.resultType = .resultTypeCount
            
            do {
                let result = try viewContext.execute(batchDelete) as! NSBatchDeleteResult
                print("Deleted \(result.result!) kind 1 or 7 events")
            } catch {
                print("Failed to delete kind 1 or 7 data")
            }
        }
        
        // KIND 0
        // ALLES WEG WANT IEDERE KIND 0 HEEFT EEN CONTACT
        // EIGEN KIND 0 NIET WEG
        viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
            fetchRequest.predicate = NSPredicate(format: "(kind == 0) AND NOT pubkey IN %@", ownAccountPubkeys)
            
            let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDelete.resultType = .resultTypeCount
            
            do {
                let result = try viewContext.execute(batchDelete) as! NSBatchDeleteResult
                print("Deleted \(result.result!) kind=0 events")
            } catch {
                print("Failed to delete kind=0 data")
            }
        }
        
        do {
            //                try viewContext.save()
            try viewContext.save()
        }
        catch {
            print("maintenance error on save(): \(error)")
        }
    }
    
    func clearImageCache() {
        // Kingfisher
//        ImageCache.default.clearMemoryCache()
//        ImageCache.default.clearDiskCache { print("Done"); imageCacheSize = 0 }
    }
    
    func removeOlderKind3Events() {
        let r = NSFetchRequest<Event>(entityName: "Event")
        r.predicate = NSPredicate(format: "kind == 3")
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        let kind3 = try! viewContext.fetch(r)
        
        var noDuplicates:Dictionary<String, Event> = [:]
        var forDeletion:[Event] = []
        
        for event in kind3 {
            if noDuplicates[event.pubkey!] != nil {
                forDeletion.append(event)
            }
            else {
                noDuplicates[event.pubkey!] = event
            }
        }
        print("going to delete \(forDeletion.count) kind 3 events")
        for toDelete in forDeletion {
            viewContext.delete(toDelete)
        }
        
        do {
            try viewContext.save()
        }
        catch {
            print("removeOlderKind3Events error on save(): \(error)")
        }
    }
    
    var body: some View {
        VStack {
            RelaysView()
            
            Toggle(isOn: $devToggle) { Text("Dev mode") }.padding(10)
            if (devToggle) {
                List {
                    Group {
                        
                        Button { removeOlderKind3Events() } label: {
                            Text("Remove older kind 3 events")
                        }.padding(5)
                        
                        Button { maintenance() } label: {
                            Text("Clean up older than 3 days!")
                        }.padding(5)
                        
                        Button { rebuildReplyToIdsCache() } label: {
                            Text("Rebuild replyToId, replyToRootId, firstQuoteId cache")
                        }.padding(5)
                        
                        Button { rebuildCountingCache() } label: {
                            Text("Rebuild counting cache (likes, mentions, replies)")
                        }.padding(5)
                        
                        Button { rebuildContactCache() } label: {
                            Text("Rebuild contact cache (banner, picture etc)")
                        }.padding(5)
                    }
                    
                    Group {
                        Button { deleteAll = true } label: {
                            Text("Delete all contacts \(allContacts.count)")
//                            Text("Delete all contacts \(allContacts.count)")
                        }.confirmationDialog("SURE???", isPresented: $deleteAll, actions: {
                            Button("YES DELETE ALL", role: .destructive) { deleteAllContacts() }
                        })
                        .padding(5)
                        
                        Button { showDeleteAllEventsConfirmation = true } label: {
                            Text("Delete all events \(allEvents.count)")
//                            Text("Delete all events \(allEvents.count)")
                        }.confirmationDialog("DELETE ALL EVENTS????", isPresented: $showDeleteAllEventsConfirmation) {
                            Button("YES DELETE ALL", role: .destructive) {
                                deleteAllEvents()
                            }
                        }
                        .padding(5)
                        
                        Button { fixContactEventRelations() } label: {
                            Text("Fix event.contact relation")
                        }.padding(5)
                        
                        Button { fixReplyToEventRelations()
                        } label: { Text("Fix reply, quote relations") }.padding(5)
                        
                        Button { clearImageCache()} label: {
                            Text("Clear image cache \(imageCacheSize) MB")
                        }
                    }
                    
                    
                    Group {
                        Text("**Umb** [@Snowden](nostur:p:4523be58d395b1b196a9b8c82b038b6895cb02b683d0c253a955068dba1facd0)")
                        Text("**Umb** [@callebtc](nostur:p:50d94fc2d8580c682b071a542f8b1e31a200b0508bab95a33bef0855df281d63) 'n")
                    }
                }
                .onAppear {
                    // Kingfisher
//                    ImageCache.default.calculateDiskStorageSize { result in
//                        switch result {
//                            case .success(let size):
//                                imageCacheSize = floor(Double(size) / 1024 / 1024)
//                                print("Disk cache size: \(imageCacheSize) MB")
//                            case .failure(let error):
//                                print(error)
//                        }
//                    }
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

