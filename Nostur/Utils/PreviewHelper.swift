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

extension View {
        
    func withPreviewEnvironment() -> some View {
        
        let userDefaults:UserDefaults = {
            let d = UserDefaults(suiteName: "preview_user_defaults")!
            d.set(PREVIEW_ACCOUNT_ID, forKey: "activeAccountPublicKey")
            d.set(true, forKey: "devToggle")
            d.set("Following", forKey: "selected_subtab")
            d.set("Main", forKey: "selected_tab")
            return d
        }()
        
        let ns:NosturState = .shared
        let sp:SocketPool = .shared
        let er:ExchangeRateModel = .shared
        let tm:DetailTabsModel = .shared
        let dim:DIMENSIONS = .shared
        let ss:SettingsStore = .shared
        let sm = SideBarModel()
        
        let previewContext = EventsProvider.preview.container.viewContext
        
        let account = PreviewFetcher.fetchAccount(PREVIEW_ACCOUNT_ID, context: previewContext)
        if let clNevent = PreviewFetcher.fetchEvents(PREVIEW_ACCOUNT_ID, kind: 3, context: previewContext).first?.toNEvent() {
            Account.preFillReadOnlyAccountFollowing(event: clNevent, context: previewContext, forceOverwrite: true)
        }
        ns.setAccount(account: account)

        return self.defaultAppStorage(userDefaults)
            .environment(\.managedObjectContext,
                          previewContext)
            .environmentObject(ns)
            .environmentObject(sp)
            .environmentObject(er)
            .environmentObject(ss)
            .environmentObject(sm)
            .environmentObject(tm)
            .environmentObject(dim)
    }
}

struct PreviewFetcher {
    
    static let viewContext = EventsProvider.preview.container.viewContext
    
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
        return nil
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
