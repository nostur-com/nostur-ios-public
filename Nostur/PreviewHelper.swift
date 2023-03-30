//
//  PreviewHelper.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/01/2023.
//

import SwiftUI
import CoreData

extension View {
        
    func withPreviewEnvironment() -> some View {
        
        let userDefaults:UserDefaults = {
            let d = UserDefaults(suiteName: "preview_user_defaults")!
            
            
            d.set("9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                  forKey: "activeAccountPublicKey")
            
//            d.set("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0",
//                  forKey: "activeAccountPublicKey")
            
            d.set(true, forKey: "devToggle")
            
            d.set(true, forKey: "showReplies")
            
            return d
        }()
        
        // "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
        let dp = DataProvider(container: EventsProvider.preview.container)
        let ns:NosturState = .shared
        let sp:SocketPool = .shared
        let nav: NavigationModel = .shared
        let er:ExchangeRateModel = .shared
        let tm:DetailTabsModel = .shared
        
        let ss = SettingsStore()
        let sm = SideBarModel()
        
        let account = PreviewFetcher.fetchAccount("9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", context: EventsProvider.preview.container.viewContext)
//
//        let account = PreviewFetcher.fetchAccount("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", context: EventsProvider.preview.container.viewContext)
        
        ns.setAccount(account: account)

        let clNevent = PreviewFetcher.fetchEvent("4d3003122620900ac5f39d4bd78bd5e82ef3f15d7538651700c90e9c56dcb964")!.toNEvent()
        Account.preFillReadOnlyAccountFollowing(event: clNevent, context: EventsProvider.preview.container.viewContext, forceOverwrite: true)

        
        return self.defaultAppStorage(userDefaults)
            .environment(\.managedObjectContext,
                          EventsProvider.preview.container.viewContext)
            .environmentObject(dp)
            .environmentObject(ns)
            .environmentObject(sp)
            .environmentObject(nav)
            .environmentObject(er)
//            .environmentObject(ds)
            .environmentObject(ss)
            .environmentObject(sm)
            .environmentObject(tm)
    }
}

struct PreviewFetcher {
    
    static let viewContext = EventsProvider.preview.container.viewContext
    
    static func allContacts(context:NSManagedObjectContext? = nil) -> [Contact] {
        let request = NSFetchRequest<Contact>(entityName: "Contact")
        request.sortDescriptors = []

        if (context != nil) {
            return try! context!.fetch(request)
        }
        return try! PreviewFetcher.viewContext.fetch(request)
    }
    
    static func fetchEvents(_ pubkey:String, kind:Int? = nil, context:NSManagedObjectContext? = nil) -> [Event] {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.entity = Event.entity()
        if (kind != nil) {
            request.predicate = NSPredicate(format: "pubkey == %@ AND kind == %d", pubkey, kind!)
        } else {
            request.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        
        if (context != nil) {
            return try! context!.fetch(request)
        }
        return try! PreviewFetcher.viewContext.fetch(request)
    }
    
    static func fetchEvents(_ pubkeys:Set<String>, kind:Int? = nil, context:NSManagedObjectContext? = nil) -> [Event] {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.entity = Event.entity()
        if (kind != nil) {
            request.predicate = NSPredicate(format: "pubkey IN %@ AND kind == %d", pubkeys, kind!)
        } else {
            request.predicate = NSPredicate(format: "pubkey IN %@", pubkeys)
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        
        if (context != nil) {
            return try! context!.fetch(request)
        }
        return try! PreviewFetcher.viewContext.fetch(request)
    }
    
    static func fetchAccount(_ pubkey:String? = nil, context:NSManagedObjectContext? = nil) -> Account? {
        let accountKey = pubkey ?? "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
        let request = NSFetchRequest<Account>(entityName: "Account")
        request.predicate = NSPredicate(format: "publicKey == %@", accountKey)
        request.sortDescriptors = []
        
        if (context != nil) {
            return try! context!.fetch(request).first
        }
        return try! PreviewFetcher.viewContext.fetch(request).first
    }
    
    static func fetchEvent(_ id:String? = nil, context:NSManagedObjectContext? = nil) -> Event? {
        let request = NSFetchRequest<Event>(entityName: "Event")
        if id != nil {
            request.predicate = NSPredicate(format: "id == %@", id!)
        }
        else {
            request.predicate = NSPredicate(format: "kind == 1")
        }
        request.sortDescriptors = []
        
        if (context != nil) {
            return try! context!.fetch(request).randomElement()
        }
        return try! PreviewFetcher.viewContext.fetch(request).randomElement()
    }
    
    static func fetchVPost(_ id:String? = nil, context:NSManagedObjectContext? = nil) -> VPost? {
        if let event = fetchEvent(id) {
            return event.toVPost()
        }
        return nil
    }
    
    static func fetchContact(_ pubkey:String, context:NSManagedObjectContext? = nil) -> Contact? {
        let request = NSFetchRequest<Contact>(entityName: "Contact")
//        request.entity = Contact.entity()
        request.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        request.sortDescriptors = []
        
        if (context != nil) {
            return try! context!.fetch(request).first
        }
        return try! PreviewFetcher.viewContext.fetch(request).first
    }
}
