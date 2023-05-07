//
//  PreviewHelper.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/01/2023.
//

import SwiftUI
import CoreData

// "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
let PREVIEW_ACCOUNT_ID = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"

class PreviewEnvironment {
    static let shared = PreviewEnvironment()
    
    let ns:NosturState = .shared
    let sp:SocketPool = .shared
    let er:ExchangeRateModel = .shared
    let tm:DetailTabsModel = .shared
    let dim:DIMENSIONS = .shared
    let ss:SettingsStore = .shared
    let sm = SideBarModel()
    let userDefaults:UserDefaults
    let context:NSManagedObjectContext
    
    init() {
        self.userDefaults = {
            let d = UserDefaults(suiteName: "preview_user_defaults")!
            d.set(PREVIEW_ACCOUNT_ID, forKey: "activeAccountPublicKey")
            d.set(true, forKey: "devToggle")
            d.set("Following", forKey: "selected_subtab")
            d.set("Main", forKey: "selected_tab")
            d.set(false, forKey: "full_width_images")
            return d
        }()
        
        self.context = DataProvider.shared().container.viewContext
        
        context.performAndWait {
            let account = Account(context: self.context)
            account.createdAt = Date()
            account.id = UUID()
            account.publicKey = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
            account.display_name = "bitcoiner_since_2013 ⚡️"
            account.name = "bitcoinerrrrr"
            account.about = "test account"
            
            let account3 = Account(context: self.context)
            account3.createdAt = Date()
            account3.id = UUID()
            account3.publicKey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
            account3.display_name = "Fabian"
            account3.name = "Fabian"
            account3.nip05 = "Fabian@nostur.com"
            account3.about = "Author of Nostur.com"
            account3.picture = "https://profilepics.nostur.com/profilepic_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/profilepic.jpg?1682440972"
            account3.banner = "https://profilepics.nostur.com/banner_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/banner.jpg?1682440972"
    //        account3.banner = "https://nostur.com/fabian/banner.jpg"
                    
//            let keys = NKeys.newKeys()
            
            let xaccount = Account(context: self.context)
            xaccount.createdAt = Date()
            xaccount.id = UUID()
            xaccount.publicKey = "11707ab5c187f4534ea7b4ad67cd9914cd07f7812b5ea2fdd91685ac84c91f5b"
    //        xaccount.privateKey = "184a90b0cbdf4b4a318d33f6464593d9936430c6793fed82d9b6ec3b8f12804f"
            xaccount.display_name = "The Ellen"
            xaccount.name = "eltje"
            xaccount.about = "Test"
            
            let relay = Relay(context: self.context)
            relay.url = "ws://localhost:3000"
            relay.createdAt = Date()
            relay.id = UUID()
            relay.read = false
            relay.write = false
            
            let contact = Contact(context: self.context)
            contact.pubkey = "11707ab5c187f4534ea7b4ad67cd9914cd07f7812b5ea2fdd91685ac84c91f5b"
            contact.about = "test"
            contact.lud16 = ""
            contact.lud06 = ""
            contact.name = "yo"
            contact.nip05 = ""
            contact.updated_at = 0
            contact.metadata_created_at = 0
            
            var messages:[String] = []
            messages.append(contentsOf: test1())
            
            messages.append(contentsOf: testMinimal())
            print("1 \(messages.count)")
            messages.append(contentsOf: testKind0Events())
            print("2 \(messages.count)")
            messages.append(contentsOf: testKind3Events())
            print("3 \(messages.count)")
            messages.append(contentsOf: testKind1Events())
            print("4 \(messages.count)")
//            messages.append(contentsOf: testKindMixedOldDunnoEvents())
            print("5 \(messages.count)")
            messages.append(contentsOf: testRepliesAndReactions())
            print("6 \(messages.count)")
//            messages.append(contentsOf: testSnowden())
            print("7 \(messages.count)")
//            messages.append(contentsOf: testBadges())
            print("8 \(messages.count)")
    //        messages.append(contentsOf: testMentions())
            print("9 \(messages.count)")
            messages.append(contentsOf: testKind6Events())
            print("10 \(messages.count)")
//            messages.append(contentsOf: testEfilter())
            print("11 \(messages.count)")
            messages.append(contentsOf: testZaps())
            print("12 \(messages.count)")
            messages.append(contentsOf: testSomeFakeAndRealZaps())
            print("13 \(messages.count)")
//            messages.append(contentsOf: testNotifications())
            print("14 \(messages.count)")
            messages.append(contentsOf: testImages())
            print("15 \(messages.count)")
//            messages.append(contentsOf: testThread())
            print("16 \(messages.count)")
            messages.append(contentsOf: testDMs())
            print("17 \(messages.count)")
            messages.append(contentsOf: testTimelineThreads())
            print("18 \(messages.count)")
            messages.append(contentsOf: testGifAndVideo())
            print("19 \(messages.count)")
            messages.append(contentsOf: testHighlights())
            print("20 \(messages.count)")
            
            var relayMessages:[RelayMessage] = []
            
            for text in messages {
                guard let message = try? RelayMessage.parseRelayMessage(text: text, relay: "wss://memory", skipValidation: true) else { continue }
                // just take all:
                relayMessages.append(message)
                // end of just take all.
    //            if (message.event?.kind == .badgeDefinition || message.event?.kind == .zapNote || message.event?.kind == .textNote || message.event?.kind == .reaction || message.event?.kind == .setMetadata) {
    //
    //                if (message.subscriptionId == nil) {
    //                    print("WHERE IS SUBSCRIPTION ID BRO")
    //                    continue
    //                }
    //                relayMessages.append(message)
    //            }
            }
            
            for relayMessage in relayMessages {
                var event = relayMessage.event!
                
                // no need for preview
    //            guard try event.verified() else {
    //                print("😡😡 hey invalid sig yo 😡😡")
    //                continue
    //            }
                
                // ANNOYING FIX FOR KIND 6 WITH JSON STRING OF ANOTHER EVENT IN EVENT.CONTENT. WTF
                if event.kind == .repost && event.content.prefix(2) == #"{""# {
                    let decoder = JSONDecoder()
                    if let noteInNote = try? decoder.decode(NEvent.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) {
                        _ = Event.saveEvent(event: noteInNote)
                        event.content = "#[0]"
                        if let firstTag = event.tags.first {
                            if firstTag.type == "e" {
                                event.tags[0] = NEventTag(type: "e", otherInformation: firstTag.id, "", "mention")
                            }
                        }
                    }
                }
                
                let savedEvent = Event.saveEvent(event: event)
                
                if event.kind == .setMetadata {
                    Contact.saveOrUpdateContact(event: event)
                }
                
                // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                if event.kind == .zapNote {
                    let _ = Event.updateZapTallyCache(savedEvent, context: self.context)
                }
                
    //            // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
    //            if event.kind == .custom(7) {
    //                do { try _ = Event.updateLikeCountCache(event.tags, content:event.content, context: context) } catch {
    //                    print("🦋🦋🔴🔴🔴 problem updating Like Count Cache .id \(event.id)")
    //                }
    //            }
    //
    //            // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REPLIES, MENTIONS)
    //            if event.kind == .textNote {
    //                // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
    //                do { try _ = Event.updateMentionsCountCache(event.tags, context: context) } catch {
    //                    print("🦋🦋🔴🔴🔴 problem updateMentionsCountCache .id \(event.id)")
    //                }
    //
    //                // NIP-10: Those marked with "reply" denote the id of the reply event being responded to.
    //                // NIP-10: Those marked with "root" denote the root id of the reply thread being responded to.
    //                do { try _ = Event.updateRepliesCountCache(event.tags, context: context) } catch {
    //                    print("🦋🦋🔴🔴🔴 problem updateRepliesCountCache .id \(event.id)")
    //                }
    //            }
                
            }
            
            if let someEvent = PreviewFetcher.fetchEvent(
                "b9b337e5730eb83af2f6ae71b65295db8fe241aec7beb7fd8b6c0b88cc3d05d1", context: self.context) {
                account.addToBookmarks(someEvent)
                someEvent.addToBookmarkedBy(account)
            }
            
            if let contact1 = PreviewFetcher.fetchContact(
                "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", context: self.context) {
                account.addToFollows(contact1)
                account.blockedPubkeys_ = account.blockedPubkeys_ + [contact1.pubkey]
                xaccount.addToFollows(contact1)
            }
            
            
            if let contact2 = PreviewFetcher.fetchContact(
                "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240", context: self.context) {
                account.addToFollows(contact2)
                contact2.nip05 = "snowden@citizenfour.com"
                contact2.nip05verifiedAt = Date.now
                account.addToFollows(contact2)
            }
            
            
            if let contact3 = PreviewFetcher.fetchContact(
                "df8efff2bfc02d81f93c7ff6ae111541637e0b3a4caff9ad48939a2f2f283be2", context: self.context) {
                account.blockedPubkeys_ = account.blockedPubkeys_ + [contact3.pubkey]
                account.addToFollows(contact3)
            }
            
           
            
            if let contact4 = PreviewFetcher.fetchContact(
                "4742221ccfbe3bee6d5823715df6864ec45dd8e6bf619527463716fe79a06427", context: self.context) {
                account3.addToFollows(contact4)
            }
            
            if let contact5 = PreviewFetcher.fetchContact(
                "4eb88310d6b4ed95c6d66a395b3d3cf559b85faec8f7691dafd405a92e055d6d", context: self.context) {
                account3.addToFollows(contact5)
            }
            
            if let c = PreviewFetcher.fetchContact("3d2e51508699f98f0f2bdbe7a45b673c687fe6420f466dc296d90b908d51d594", context: self.context) {
                account3.addToFollows(c) // MATT
            }
            if let c = PreviewFetcher.fetchContact("6f35047caf7432fc0ab54a28fed6c82e7b58230bf98302bf18350ff71e10430a", context: self.context) {
                account3.addToFollows(c) // WILL
            }
            if let c = PreviewFetcher.fetchContact("de7ecd1e2976a6adb2ffa5f4db81a7d812c8bb6698aa00dcf1e76adb55efd645", context: self.context) {
                account3.addToFollows(c) // MELVIN
            }
            
            account3.blockedPubkeys_.append("743416b4943b20b8e1ed6c6d8fc81bbb7a27797c4cd3acafae4cc3d1ed67dd4d;")
            
            NosturList.generateExamples(context: self.context)
            
            // make some random private notes
            
            let randomTextEventsR = Event.fetchRequest()
            randomTextEventsR.fetchLimit = 10
            randomTextEventsR.fetchOffset = Int.random(in: 0..<100)
            randomTextEventsR.predicate = NSPredicate(format: "kind == 1")
            let randomTextEvents = try? self.context.fetch(randomTextEventsR)
            if let randomTextEvents {
                for _ in 0..<10 {
                    let privateNote = PrivateNote(context: self.context)
                    privateNote.content = ["Some more text here, I think I need to fix this in some way or another, I don't know how yet. But this text is a bit longer.","I made a private note here\nYo!","I made a private note here\nWith some more lines\n\nCool", "This is good"].randomElement()!
                    privateNote.by = [account,account3].randomElement()
                    privateNote.post = randomTextEvents.randomElement()
                    privateNote.createdAt = Date.now
                    privateNote.updatedAt = Date.now
                }
            }
            
            let randomContactsR = Contact.fetchRequest()
            randomContactsR.fetchLimit = 10
            randomContactsR.fetchOffset = Int.random(in: 0..<100)
            let randomContacts = try? self.context.fetch(randomContactsR)
            if let randomContacts {
                for _ in 0..<10 {
                    let privateNote = PrivateNote(context: self.context)
                    privateNote.content = ["Some more text here, I think I need to fix this in some way or another, I don't know how yet. But this text is a bit longer.","I made a private note here\nYo!","I made a private note here\nWith some more lines\n\nCool", "This is good"].randomElement()!
                    privateNote.by = [account,account3].randomElement()
                    privateNote.contact = randomContacts.randomElement()
                    privateNote.createdAt = Date.now
                    privateNote.updatedAt = Date.now
                }
            }
            print ("☢️☢️☢️ LOADED (SHOULD ONLY APPEAR ONCE) ☢️☢️☢️")
        }
        
        let account = PreviewFetcher.fetchAccount(PREVIEW_ACCOUNT_ID, context: self.context)
        if let clNevent = PreviewFetcher.fetchEvents(PREVIEW_ACCOUNT_ID, kind: 3, context: self.context).first?.toNEvent() {
            Account.preFillReadOnlyAccountFollowing(event: clNevent, context: self.context, forceOverwrite: true)
        }
        ns.setAccount(account: account)
    }
    
}

extension View {
        
    func withPreviewEnvironment() -> some View {
        
        let pe:PreviewEnvironment = .shared

        return self.defaultAppStorage(pe.userDefaults)
            .environment(\.managedObjectContext,
                          pe.context)
            .environmentObject(pe.ns)
            .environmentObject(pe.sp)
            .environmentObject(pe.er)
            .environmentObject(pe.ss)
            .environmentObject(pe.sm)
            .environmentObject(pe.tm)
            .environmentObject(pe.dim)
    }
}

struct PreviewFetcher {
    
    static let viewContext = DataProvider.shared().container.viewContext
    
    static func allContacts(context:NSManagedObjectContext? = nil) -> [Contact] {
        let request = NSFetchRequest<Contact>(entityName: "Contact")
        request.sortDescriptors = []

        return try! (context ?? PreviewFetcher.viewContext).fetch(request)
    }
    
    static func fetchEvents(_ pubkey:String, kind:Int? = nil, context:NSManagedObjectContext? = nil) -> [Event] {
        let request = Event.fetchRequest()
//        request.entity = Event.entity()
        if (kind != nil) {
            request.predicate = NSPredicate(format: "pubkey == %@ AND kind == %d", pubkey, kind!)
        } else {
            request.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        
        return try! (context ?? PreviewFetcher.viewContext).fetch(request)
    }
    
    static func fetchEvents(_ pubkeys:Set<String>, kind:Int? = nil, context:NSManagedObjectContext? = nil) -> [Event] {
        let request = Event.fetchRequest()
//        request.entity = Event.entity()
        if let kind {
            request.predicate = NSPredicate(format: "pubkey IN %@ AND kind == %d", pubkeys, kind)
        } else {
            request.predicate = NSPredicate(format: "pubkey IN %@", pubkeys)
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        
        return (try? (context ?? PreviewFetcher.viewContext).fetch(request)) ?? []
    }
    
    static func fetchAccount(_ pubkey:String? = nil, context:NSManagedObjectContext? = nil) -> Account? {
        let accountKey = pubkey ?? PREVIEW_ACCOUNT_ID
        let request = Account.fetchRequest()
//        let request = NSFetchRequest<Account>(entityName: "Account")
        request.predicate = NSPredicate(format: "publicKey == %@", accountKey)
        request.sortDescriptors = []
        return try! (context ?? PreviewFetcher.viewContext).fetch(request).first
    }
    
    static func fetchEvent(_ id:String? = nil, context:NSManagedObjectContext? = nil) -> Event? {
        let request = Event.fetchRequest()
//        let request = NSFetchRequest<Event>(entityName: "Event")
        if id != nil {
            request.predicate = NSPredicate(format: "id == %@", id!)
        }
        else {
            request.predicate = NSPredicate(format: "kind == 1")
        }
        return try! (context ?? PreviewFetcher.viewContext).fetch(request).randomElement()
    }
    
    static func fetchVPost(_ id:String? = nil, context:NSManagedObjectContext? = nil, plainText:Bool = false) -> VPost? {
        if let event = fetchEvent(id) {
            return event.toVPost(plainText: plainText)
        }
        else {
            return fetchEvent()?.toVPost()
        }
    }
    
    static func fetchContact(_ pubkey:String? = nil, context:NSManagedObjectContext? = nil) -> Contact? {
        let request = Contact.fetchRequest()
        if pubkey != nil {
            request.predicate = NSPredicate(format: "pubkey == %@", pubkey!)
        }
        return try! (context ?? PreviewFetcher.viewContext).fetch(request).randomElement()
    }
    
    static func fetchList(context:NSManagedObjectContext? = nil) -> NosturList? {
        let request = NosturList.fetchRequest()
        return try! (context ?? PreviewFetcher.viewContext).fetch(request).randomElement()
    }
}
