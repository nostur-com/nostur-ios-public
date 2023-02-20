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
    
    func deleteAllTags() {
        let r = Tag.fetchRequest()
        let allTags = try! viewContext.fetch(r)
        
        for tag in allTags {
            viewContext.delete(tag)
        }
    }
    
    // SCANS 1,9735,6
    // DELETES ALL TAGS AND RECREATES FROM 1,9735,6
    // NILS -> replyToId, replyToRootId, firstQuoteId
    //   AND FILLS AGAIN FROM tagsSerialized
    func rebuildReplyToIdsCache() {
        SavedEventsCache.shared.clear()
        
        
        let r = NSFetchRequest<Event>(entityName: "Event")
        r.predicate = NSPredicate(format: "kind IN {1,9735,6}") // Also 9735 to fix .tags on Zaps
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        let kind1 = try! viewContext.fetch(r)
        
        
        // First delete all tags
        deleteAllTags()
        
        // ON FIRST PASS RESET ALL TO NIL
        for event in kind1 {
            event.replyToId = nil
            event.replyToRootId = nil
            event.firstQuoteId = nil
        }
        
        let decoder = JSONDecoder()
        
        for event in kind1 {  // Also 9735 to fix .tags on Zaps
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
                    
                    
                    // TAGS: do tags, for just .textNote? or all? or..?
                    event.tags = NSOrderedSet(array: tags.map({ nTag in
                        let tag = Tag(context: viewContext)
                        tag.type = nTag.type
                        if (tag.type == "e") {
                            tag.event = try? Event.fetchEvent(id: nTag.id, context: viewContext)
                        }
                        else if (tag.type == "p") {
                            tag.contact = Contact.fetchByPubkey(nTag.pubkey, context: viewContext)
                        }
                        tag.index1 = nTag.otherInformation[safe: 0]
                        tag.index2 = nTag.otherInformation[safe: 1]
                        tag.index3 = nTag.otherInformation[safe: 2]
                        tag.index4 = nTag.otherInformation[safe: 3]
                        
                        return tag
                    }))
                    
//                    // TAGS INVERSE:
//                    let er = NSFetchRequest<Tag>(entityName: "Tag")
//                    er.predicate = NSPredicate(format: "type == 'e' AND index1 == %@", event.id!)
//                    if let tags = try? viewContext.fetch(er) {
//                        for tag in tags {
//                            tag.event = event
//                            tag.objectWillChange.send()
//                        }
//                    }
                }
            }
        }
        
        do {
            //                try viewContext.save()
            try viewContext.save()
        }
        catch {
            print("🔴 rebuildReplyToIdsCache error on save(): \(error)")
        }
        
    }
    
    // TAKES ALL 1,7,9735 (NOTES, REACTIONS, ZAPS) Not reposts? 6?
    // RESET ALL COUNTERS TO 0
    func rebuildCountingCache() {
        SavedEventsCache.shared.clear()
        
        // sort events by date. oldest first
        let r = NSFetchRequest<Event>(entityName: "Event")
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        let allEvents = try! viewContext.fetch(r)
        
        let kind1or7or9735 = allEvents.filter { $0.kind == 1 || $0.kind == 7 || $0.kind == 9735 }
        let kind1 = allEvents.filter { $0.kind == 1 }
        
        let decoder = JSONDecoder()
        
        // ON FIRST PASS RESET ALL COUNTERS TO 0 (FOR KIND 1)
        for event in kind1 {
            event.repliesCount = 0 // TODO: Dit allemaal kan @aggregate worden?? @count ofzo?
            event.mentionsCount = 0
            event.likesCount = 0
            event.zapTally = 0
            event.zapsCount = 0
        }
        
        // RECOUNT
        for event in kind1or7or9735 {
            
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
            
            
            // if ZAP (KIND 9735)
            // update likes count
            if (event.kind == 9735 && event.tagsSerialized != nil) {
                let _ = Event.updateZapTallyCache(event, context: viewContext)
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
        sendNotification(.willDeleteAllEvents, nil)
        SavedEventsCache.shared.clear()
        
        let r = NSFetchRequest<Event>(entityName: "Event")
        let allEvents = try! viewContext.fetch(r)
        
        for event in allEvents {
            viewContext.delete(event)
        }
        do {
            print("deleting \(allEvents.count) events.")
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
            print("🔴 fixContactEventRelations error on save(): \(error)")
            print(error)
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
                    Text("Using these may hang the app for a minute:")
                    Group {
                        
                        Button { removeOlderKind3Events() } label: {
                            Text("Remove old contact lists (kind=3)")
                        }
                        
                        Button { Maintenance.maintenance(context: viewContext) } label: {
                            Text("Clean up older than 3 days")
                        }
                        
                        Button { rebuildReplyToIdsCache() } label: {
                            Text("Rebuild reply and quote cache")
                        }
                        
                        Button { rebuildCountingCache() } label: {
                            Text("Rebuild counter cache (likes, mentions, replies)")
                        }
                        
                        Button { rebuildContactCache() } label: {
                            Text("Rebuild contact cache (banner, picture etc)")
                        }
                    }
                    
                    Group {
                        Button { deleteAll = true } label: {
                            Text("Delete all contacts \(allContacts.count)")
                        }.confirmationDialog("SURE???", isPresented: $deleteAll, actions: {
                            Button("YES DELETE ALL", role: .destructive) { deleteAllContacts() }
                        })
                        
                        Button { showDeleteAllEventsConfirmation = true } label: {
                            Text("Delete all events \(allEvents.count)")
                        }.confirmationDialog("DELETE ALL EVENTS????", isPresented: $showDeleteAllEventsConfirmation) {
                            Button("YES DELETE ALL", role: .destructive) {
                                deleteAllEvents()
                            }
                        }
                        
                        Button { fixContactEventRelations() } label: {
                            Text("Fix event.contact relation")
                        }
                        
                        Button { fixReplyToEventRelations() } label: { Text("Fix reply, quote relations") }
                        
                        Button { clearImageCache()} label: {
                            Text("Clear image cache")
                        }
                    }
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

