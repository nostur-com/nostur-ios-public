//
//  ConfigurationView.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2023.
//

import SwiftUI
import CoreData
import LightningDevKit
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
        
        // ON FIRST PASS RESET ALL TO NIL
        for event in kind1 {
            event.replyToId = nil
            event.replyToRootId = nil
            event.firstQuoteId = nil
            
            event.zappedEventId = nil
            event.zappedContactPubkey = nil
            
            event.reactionToId = nil
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
                    
                    if event.kind == 9735 {
                        if let firstE = event.firstE() {
                            event.zappedEventId = firstE
                        }
                        if let firstP = event.firstP() {
                            event.zappedContactPubkey = firstP
                        }
                    }
                    
                    if event.kind == 7 {
                        if let lastE = event.lastE() {
                            event.reactionToId = lastE
                        }
                        
                        // TODO: dont need this?
            //            if let lastP = event.lastP() {
            //                event.reactionToContactId = lastP
            //            }
                    }
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
    
    
    func putContactsInEventsForPs() {
        SavedEventsCache.shared.clear()
        let c = Contact.fetchRequest()
        c.predicate = NSPredicate(format: "updated_at != 0")
        if let contacts = try? viewContext.fetch(c) {
            for contact in contacts {
                
                let tr = NSFetchRequest<Event>(entityName: "Event")
                tr.predicate = NSPredicate(format: "kind IN {1,6,7,9734} AND tagsSerialized CONTAINS %@", contact.pubkey) // OPTIMIZATION HACK
                if let events = try? viewContext.fetch(tr) {
                    for event in events {
                        event.addToContacts(contact)
                    }
                }
                
            }
        }
        do {
            try viewContext.save()
            print("finished putting contacts in events for their p's")
        }
        catch {
            print("putContactsInEventsForPs error on save(): \(error)")
            print(error)
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
//            event.cachedSats = 0
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
            // update sats cache --- replaced with .naiveSats
            if (event.kind == 9735 && event.tagsSerialized != nil) {
//                if let bolt11 = event.bolt11() {
//                    let invoice = Invoice.fromStr(s: bolt11)
//                    if let parsedInvoice = invoice.getValue() {
//                        event.cachedSats = Double((parsedInvoice.amountMilliSatoshis() ?? 0) / 1000)
//                    }
//                }
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
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
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
                try Contact.updateMetadata(metaData, pubkey: event.pubkey, context: viewContext)
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
        
        let e = NSFetchRequest<Event>(entityName: "Event")
        e.predicate = NSPredicate(format: "kind == 0")
        let allMetadata = try! viewContext.fetch(e)
        
        for event in allMetadata {
            viewContext.delete(event)
        }
        
        do {
            print("deleting \(allContacts.count) contacts. and \(allMetadata.count) events. (Contact+EVENT.0")
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
            cr.predicate = NSPredicate(format: "pubkey == %@", event.pubkey)
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
        er.predicate = NSPredicate(format: "kind IN {1,6,7,9735}")
        let allKind1 = Array(try! viewContext.fetch(er))
        
        for event in allKind1 {
            event.replyTo = nil
            event.replyToRoot = nil
            event.firstQuote = nil
            
            event.zappedEvent = nil
            event.zappedContact = nil
            
            event.reactionTo = nil
            
            if (event.replyToId != nil) {
                event.replyTo = try? Event.fetchEvent(id: event.replyToId!, context: viewContext)
            }
            if (event.replyToRootId != nil) {
                event.replyToRoot = try? Event.fetchEvent(id: event.replyToRootId!, context: viewContext)
            }
            if (event.firstQuoteId != nil) {
                event.firstQuote = try? Event.fetchEvent(id: event.firstQuoteId!, context: viewContext)
            }
            if (event.kind == 9735) {
                if let nZapReq = Event.extractZapRequest(tags: event.tags()) {
                    event.zapFromRequest = try? Event.fetchEvent(id: nZapReq.id, context: viewContext)
                }
                if (event.zappedContactPubkey != nil) {
                    event.zappedContact = Contact.fetchByPubkey(event.zappedContactPubkey!, context: viewContext)
                }
            }
            
            if event.kind == 7 {
                if (event.reactionToId != nil) {
                    event.reactionTo = try? Event.fetchEvent(id: event.reactionToId!, context: viewContext)
                }
                
                // TODO: dont need this?
//                if (event.reactionToContactId != nil) {
//                    event.reactionToContact = try? Event.fetchEvent(id: event.reactionToContactId!, context: viewContext)
//                }
            }
        }
        
        do {
            print("Rebuilt event.replyTo, event.replyToRoot, event.firstQuote, event.zappedEvent, event.reactionTo relations")
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
            if noDuplicates[event.pubkey] != nil {
                forDeletion.append(event)
            }
            else {
                noDuplicates[event.pubkey] = event
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
                            Button("YES DELETE ALL CONTACTS", role: .destructive) { deleteAllContacts() }
                        })
                        
                        Button { showDeleteAllEventsConfirmation = true } label: {
                            Text("Delete all events \(allEvents.count)")
                        }.confirmationDialog("DELETE ALL EVENTS????", isPresented: $showDeleteAllEventsConfirmation) {
                            Button("YES DELETE ALL EVENTS", role: .destructive) {
                                deleteAllEvents()
                            }
                        }
                        
                        Button { fixContactEventRelations() } label: {
                            Text("Fix event.contact relation")
                        }
                        
                        Button { putContactsInEventsForPs() } label: {
                            Text("Fix contacts (p) in event")
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

