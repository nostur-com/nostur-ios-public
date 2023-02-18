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
            
            d.set("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0",
                  forKey: "activeAccountPublicKey")
            
            d.set(true, forKey: "devToggle")
            
            d.set(true, forKey: "showReplies")
            
            return d
        }()
        
        // "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
        
        let sp:SocketPool = .shared
        let ns = NosturState(container: EventsProvider.preview.container)
        let nav = NavigationModel()
        let account = PreviewFetcher.fetchAccount("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", context: EventsProvider.preview.container.viewContext)
        _ = ns.loadActiveAccount(account: account)
        
        return self.defaultAppStorage(userDefaults)
            .environment(\.managedObjectContext,
                          EventsProvider.preview.container.viewContext)
            .environmentObject(ns)
            .environmentObject(sp)
            .environmentObject(EventsProvider.preview)
            .environmentObject(account!)
            .environmentObject(nav)
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
//        request.entity = Event.entity()
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
