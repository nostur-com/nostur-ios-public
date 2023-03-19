//
//  ConfigurationView.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2023.
//

import SwiftUI
import CoreData
import LightningDevKit
import Combine
//import Kingfisher

class ViewPrint: ObservableObject {
    @Published var text = "Using these may hang the app for a minute:"
    @Published var throttleText = "Using these may hang the app for a minute:"
    var subscriptions = Set<AnyCancellable>()
    init() {
        $text
            .throttle(for: .seconds(0.5), scheduler: RunLoop.main, latest: true)
            .sink { text in
                self.throttleText = text
            }
            .store(in: &subscriptions)
    }
}

struct ConfigurationView: View {
    
    @EnvironmentObject var nav:NavigationModel
    @AppStorage("devToggle") var devToggle: Bool = false
    @Environment(\.managedObjectContext) var viewContext

    @FetchRequest(fetchRequest: Contact.fetchRequest())
    var allContacts:FetchedResults<Contact>
    
    @FetchRequest(fetchRequest: Event.fetchRequest())
    var allEvents:FetchedResults<Event>
    
    @State var deleteAll = false
    @State var showDeleteAllEventsConfirmation = false
    
    @ObservedObject var vm = ViewPrint()
    
    func viewPrint(_ text:String) {
        if Thread.isMainThread {
            vm.text = text
        }
        else {
            DispatchQueue.main.async {
                vm.text = text
            }
        }
        print(text)
    }
    
    // SCANS 1,9735,6
    // DELETES ALL TAGS AND RECREATES FROM 1,9735,6
    // NILS -> replyToId, replyToRootId, firstQuoteId
    //   AND FILLS AGAIN FROM tagsSerialized

    func fixPointers() {
        SavedEventsCache.shared.clear()
    
        let bg = DataProvider.shared().newTaskContext()
        bg.perform {
            let r = NSFetchRequest<Event>(entityName: "Event")
            r.predicate = NSPredicate(format: "kind IN {1,9735,6}") // Also 9735 to fix .tags on Zaps
            r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
            let kind1 = try! bg.fetch(r)
            
            // ON FIRST PASS RESET ALL TO NIL
            var progress = 0
            for event in kind1 {
                progress += 1
                if (progress % 100 == 0) {
                    viewPrint("Setting to nil first \(progress)/\(kind1.count)")
                    do {
                        try bg.save()
                    }
                    catch {
                        viewPrint("🔴 failed to save at batch \(progress): \(error)")
                    }
                }
                event.replyToId = nil
                event.replyToRootId = nil
                event.firstQuoteId = nil
                
                event.zappedEventId = nil
                event.zappedContactPubkey = nil
                
                event.reactionToId = nil
            }
            
            let decoder = JSONDecoder()
            
            progress = 0
            for event in kind1 {  // Also 9735 to fix .tags on Zaps
                progress += 1
                if (progress % 100 == 0) {
                    print("Processing \(progress)/\(kind1.count)")
                    do {
                        try bg.save()
                    }
                    catch {
                        print("🔴 failed to save at batch \(progress): \(error)")
                    }
                }
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
                try bg.save()
                viewPrint("Finished")
            }
            catch {
                viewPrint("🔴 rebuildReplyToIdsCache error on save()")
                print(error)
            }
        }
        
    }
    
    
    func putContactsInEventsForPs() {
        SavedEventsCache.shared.clear()
        
        let bg = DataProvider.shared().newTaskContext()
        bg.perform {
            let c = Contact.fetchRequest()
            c.predicate = NSPredicate(format: "updated_at != 0")
            if let contacts = try? bg.fetch(c) {
                
                
                var progress = 0
                for contact in contacts {
                    progress += 1
                    if (progress % 100 == 0) {
                        viewPrint("Processing \(progress)/\(contacts.count)")
                        do {
                            try bg.save()
                        }
                        catch {
                            viewPrint("🔴 failed to save at batch \(progress)")
                            print(error)
                        }
                    }
                    
                    let tr = NSFetchRequest<Event>(entityName: "Event")
                    tr.predicate = NSPredicate(format: "kind IN {1,6,7,9734} AND tagsSerialized CONTAINS %@", contact.pubkey) // OPTIMIZATION HACK
                    if let events = try? bg.fetch(tr) {
                        for event in events {
                            event.addToContacts(contact)
                        }
                    }
                    
                }
            }
            do {
                try bg.save()
                viewPrint("Finished")
            }
            catch {
                viewPrint("putContactsInEventsForPs error on save(): \(error)")
            }
        }
        
    }
    
    // TAKES ALL 1,7,9735 (NOTES, REACTIONS, ZAPS) Not reposts? 6?
    // RESET ALL COUNTERS TO 0
    func rebuildCountingCache() {
        SavedEventsCache.shared.clear()
        
        let bg = DataProvider.shared().newTaskContext()
        bg.perform {
            // sort events by date. oldest first
            let r = NSFetchRequest<Event>(entityName: "Event")
            r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
            let allEvents = try! bg.fetch(r)
            
            let kind1or7or9735 = allEvents.filter { $0.kind == 1 || $0.kind == 7 || $0.kind == 9735 }
            let kind1 = allEvents.filter { $0.kind == 1 }
            
            let decoder = JSONDecoder()
            
            // ON FIRST PASS RESET ALL COUNTERS TO 0 (FOR KIND 1)
            var progress = 0
            for event in kind1 {
                progress += 1
                if (progress % 100 == 0) {
                    viewPrint("First setting to 0 \(progress)/\(kind1.count)")
                    do {
                        try bg.save()
                    }
                    catch {
                        viewPrint("🔴 failed to save at batch \(progress)")
                        print(error)
                    }
                }
                event.repliesCount = 0 // TODO: Dit allemaal kan @aggregate worden?? @count ofzo?
                event.mentionsCount = 0
                event.likesCount = 0
                event.zapTally = 0
                event.zapsCount = 0
    //            event.cachedSats = 0
            }
            
            // RECOUNT
            progress = 0
            for event in kind1or7or9735 {
                progress += 1
                if (progress % 100 == 0) {
                    viewPrint("Processing \(progress)/\(kind1or7or9735.count)")
                    do {
                        try bg.save()
                    }
                    catch {
                        viewPrint("🔴 failed to save at batch \(progress)")
                        print(error)
                    }
                }
                
                // if reply or replytoroot (and KIND 1)
                // update replies counter
                if (event.kind == 1 && event.tagsSerialized != nil) {
                    do {
                        if let tags = try? decoder.decode([NEventTag].self, from: Data(event.tagsSerialized!.utf8)) {
                            try _ = Event.updateRepliesCountCache(tags, context: bg)
                        }
                    }
                    catch {
                        viewPrint("something wrong with updating replies cache")
                        print(error)
                    }
                }
                
                
                // if reaction (KIND 7)
                // update likes count
                if (event.kind == 7 && event.tagsSerialized != nil) {
                    do {
                        try _ = Event.updateLikeCountCache(event, content:event.content ?? "", context: bg)
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
                            try _ = Event.updateMentionsCountCache(tags, context: bg)
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
                    let _ = Event.updateZapTallyCache(event, context: bg)
                }
            }
            
            
            print("Finishing up with bg.save()")
            
            do {
                try bg.save()
                viewPrint("Finished")
            }
            catch {
                viewPrint("rebuildCountingCache error on save()")
                print(error)
            }
        }
        
    }
    
    func rebuildContactCache() {
        SavedEventsCache.shared.clear()
        // update fields. BUT ALSO NIL THEM IF MISSING // TODO: SHOULD ALSO DO IN REGULAR METADATA PARSING
        
        let bg = DataProvider.shared().newTaskContext()
        viewPrint("Starting...")
        bg.perform {
            let decoder = JSONDecoder()
            
            let r = NSFetchRequest<Event>(entityName: "Event")
            r.predicate = NSPredicate(format: "kind == 0")
            r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)]
            let kind0 = try! bg.fetch(r)
            
            var progress = 0
            for event in kind0 {
                progress += 1
                if (progress % 100 == 0) {
                    viewPrint("Processing \(progress)/\(kind0.count)")
                    do {
                        try bg.save()
                    }
                    catch {
                        viewPrint("🔴 failed to save at batch \(progress)")
                        print(error)
                    }
                }
                guard event.content != nil else {
                    continue
                }
                
                guard let metaData = try? decoder.decode(NSetMetadata.self, from: Data(event.content!.utf8)) else {
                    continue
                }
                
                do {
                    print("trying to update for \(String(describing: event.pubkey))")
                    try Contact.updateMetadata(metaData, event: event, context: bg)
                }
                catch {
                    viewPrint("something wrong with updating conact info cache")
                    print(error)
                }
            }
            
            
            do {
                try bg.save()
                viewPrint("Finished rebuilding contacts cache")
            }
            catch {
                print("rebuildContactCache error on save()")
                print(error)
            }
        }
        
    }
    
    func deleteAllContacts() {
        SavedEventsCache.shared.clear()
        
        let bg = DataProvider.shared().newTaskContext()
        viewPrint("Starting...")
        bg.perform {
            let r = NSFetchRequest<Contact>(entityName: "Contact")
            let allContacts = try! bg.fetch(r)
            
            var progress = 0
            for contact in allContacts {
                progress += 1
                if (progress % 100 == 0) {
                    viewPrint("Processing \(progress)/\(allContacts.count)")
                    do {
                        try bg.save()
                    }
                    catch {
                        viewPrint("🔴 failed to save at batch \(progress): \(error)")
                    }
                }
                bg.delete(contact)
            }
            
            let e = NSFetchRequest<Event>(entityName: "Event")
            e.predicate = NSPredicate(format: "kind == 0")
            let allMetadata = try! bg.fetch(e)
            
            progress = 0
            for event in allMetadata {
                progress += 1
                if (progress % 100 == 0) {
                    viewPrint("Processing \(progress)/\(allMetadata.count)")
                    do {
                        try bg.save()
                    }
                    catch {
                        viewPrint("🔴 failed to save at batch \(progress): \(error)")
                    }
                }
                bg.delete(event)
            }
            
            do {
                try bg.save()
                viewPrint("Finished")
                print("deleted \(allContacts.count) contacts. and \(allMetadata.count) events. (Contact+EVENT.0")
            }
            catch {
                viewPrint("deleteAllContacts error on save()")
                print(error)
            }
        }
    }
    
    func deleteAllEvents() {
        sendNotification(.willDeleteAllEvents, nil)
        SavedEventsCache.shared.clear()
        
        let bg = DataProvider.shared().newTaskContext()
        viewPrint("Starting...")
        bg.perform {
            let r = NSFetchRequest<Event>(entityName: "Event")
            let allEvents = try! bg.fetch(r)
            
            var progress = 0
            for event in allEvents {
                progress += 1
                if (progress % 100 == 0) {
                    viewPrint("Processing \(progress)/\(allEvents.count)")
                    do {
                        try bg.save()
                    }
                    catch {
                        viewPrint("🔴 failed to save at batch \(progress)")
                        print(error)
                    }
                }
                bg.delete(event)
            }
            do {
                try bg.save()
                viewPrint("Finished deleting \(allEvents.count) events.")
            }
            catch {
                viewPrint("deleteAllEvents error on save()")
                print(error)
            }
        }
    }
    
    func fixContactEventRelations() {
        SavedEventsCache.shared.clear()
        
        let bg = DataProvider.shared().container.newBackgroundContext()
        viewPrint("Starting...")
        bg.perform {
            // TODO: MAybe dont need for all events??? just kind:1 is enough?
            let er = NSFetchRequest<Event>(entityName: "Event")
            er.sortDescriptors = []
            let allEvents = Array(try! bg.fetch(er))
            
            var progress = 0
            for event in allEvents {
                progress += 1
                if (progress % 100 == 0) {
                    viewPrint("Processing \(progress)/\(allEvents.count)")
                    do {
                        try bg.save()
                    }
                    catch {
                        viewPrint("🔴 failed to save at batch \(progress)")
                        print(error)
                    }
                }
                // set relation to Contact
                let cr = NSFetchRequest<Contact>(entityName: "Contact")
                cr.predicate = NSPredicate(format: "pubkey == %@", event.pubkey)
                cr.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
                if let contact = try? bg.fetch(cr).first {
                    event.contact = contact
                }
            }
            
            do {
    //            print("Rebuilt event.contact relation")
                try bg.save()
                viewPrint("Finished")
            }
            catch {
                viewPrint("fixContactEventRelations error on save()")
                print(error)
            }
        }
        
    }
    
    func fixRelations() {
        SavedEventsCache.shared.clear()
        let bg = DataProvider.shared().newTaskContext()
        viewPrint("Starting...")
        bg.perform {
            // TODO: MAybe dont need for all events??? just kind:1 is enough?
            let er = NSFetchRequest<Event>(entityName: "Event")
            er.sortDescriptors = []
            er.predicate = NSPredicate(format: "kind IN {1,6,7,9735}")
            let allKind1 = Array(try! bg.fetch(er))
            
            print("fixReplyToEventRelations for \(allKind1.count) items {1,6,7,9735}")
            var progress = 0
            for event in allKind1 {
                progress += 1
                if (progress % 100 == 0) {
                    viewPrint("Processing \(progress)/\(allKind1.count)")
                    do {
                        try bg.save()
                    }
                    catch {
                        viewPrint("🔴 failed to save at batch \(progress)")
                        print(error)
                    }
                }
                event.replyTo = nil
                event.replyToRoot = nil
                event.firstQuote = nil
                
                event.zappedEvent = nil
                event.zappedContact = nil
                
                event.reactionTo = nil
                
                if event.kind == 7 {
                    if (event.reactionToId != nil) {
                        event.reactionTo = try? Event.fetchEvent(id: event.reactionToId!, context: bg)
                    }
                    
                    // TODO: dont need this?
    //                if (event.reactionToContactId != nil) {
    //                    event.reactionToContact = try? Event.fetchEvent(id: event.reactionToContactId!, context: bg)
    //                }
                }
                else {
                    if (event.replyToId != nil) {
                        event.replyTo = try? Event.fetchEvent(id: event.replyToId!, context: bg)
                    }
                    if (event.replyToRootId != nil) {
                        event.replyToRoot = try? Event.fetchEvent(id: event.replyToRootId!, context: bg)
                    }
                    if (event.firstQuoteId != nil) {
                        event.firstQuote = try? Event.fetchEvent(id: event.firstQuoteId!, context: bg)
                    }
                    if (event.kind == 9735) {
                        if let nZapReq = Event.extractZapRequest(tags: event.tags()) {
                            event.zapFromRequest = try? Event.fetchEvent(id: nZapReq.id, context: bg)
                        }
                        if (event.zappedContactPubkey != nil) {
                            event.zappedContact = Contact.fetchByPubkey(event.zappedContactPubkey!, context: bg)
                        }
                        if (event.zappedEventId != nil) {
                            event.zappedEvent = try? Event.fetchEvent(id: event.zappedEventId!, context: bg)
                        }
                    }
                }
            }
            
            do {
                try bg.save()
                viewPrint("Finished")
            }
            catch {
                viewPrint("🔴 fixReplyToEventRelations error on save()")
                print(error)
            }
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
        viewPrint("Busy")
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
            viewPrint("Finished")
        }
        catch {
            viewPrint("removeOlderKind3Events error on save()")
            print(error)
        }
    }
    
    var body: some View {
        NavigationStack(path: $nav.configurationPath) {
            VStack {
                RelaysView()
                
                Toggle(isOn: $devToggle) {
                    VStack(alignment: .leading) {
                        Text("Dev mode")
                        if (devToggle) {
                            Text(vm.throttleText)
                        }
                    }
                }.padding(10)
                if (devToggle) {
                    List {
                        Group {
                            
                            Button { removeOlderKind3Events() } label: {
                                Text("Remove old contact lists (kind=3)")
                            }
                            
                            Button { Maintenance.maintenance(context: viewContext) } label: {
                                Text("Clean up older than 3 days")
                            }
                            
                            Button { fixPointers() } label: {
                                Text("Rebuild referenced things (tagsSerialized -> someId, anotherId)")
                            }
                            
                            Button { rebuildCountingCache() } label: {
                                Text("Rebuild counter cache (likes, mentions, replies, zaps)")
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
                            
//                            Button { fixContactEventRelations() } label: { // TODO: THIS ONE NOT NEEDED ANYMORE??
//                                Text("Fix event.pubkey -> event.contact")
//                            }
                            
                            Button { putContactsInEventsForPs() } label: {
                                Text("Fix contacts (p) in event")
                            }
                            
                            Button { fixRelations() } label: { Text("Fix relations (replyToId -> replyTo) etc") }
                            
                            Button { clearImageCache()} label: {
                                Text("Clear image cache")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Relays")
            .navigationBarTitleDisplayMode(.inline)
            .withNavigationDestinations()
        }

//        .navigationBarHidden(true)
    }
}

struct ConfigurationView_Previews: PreviewProvider {
    
    static var previews: some View {
        
        ConfigurationView()
            .withPreviewEnvironment()
    }
}

