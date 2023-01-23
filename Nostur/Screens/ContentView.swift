//
//  ContentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import CoreData

struct ContentView: View {
    
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var accountState:AccountState
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @State var path = NavigationPath()
    
    @FetchRequest(
//        entity: Contact.entity(),
//        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        sortDescriptors: [SortDescriptor(\Contact.updated_at, order: .reverse)],
        animation: .none)
    var contacts:FetchedResults<Contact> // ALL CONTACTS
    
    @FetchRequest(
//        entity: Event.entity(),
//        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)],
        sortDescriptors: [SortDescriptor(\Event.created_at, order: .forward)],
        predicate: NSPredicate(format: "kind == 1 && replyToId == nil"),
        animation: .none)
    var events: FetchedResults<Event> // NOTES (NOT REPLIES)
    
    @FetchRequest(
//        entity: Event.entity(),
//        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        sortDescriptors: [SortDescriptor(\Event.created_at, order: .forward)],
        animation: .none)
    var eventsAll: FetchedResults<Event> // NOTES AND REPLIES
    
    @FetchRequest(
//        entity: Event.entity(),
//        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        sortDescriptors: [SortDescriptor(\Event.created_at, order: .forward)],
        predicate: NSPredicate(format: "kind == 0"),
        animation: .none)
    var eventsMeta: FetchedResults<Event> // CONTACT ABOUT INFO
    
    @FetchRequest(
//        entity: Event.entity(),
//        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        sortDescriptors: [SortDescriptor(\Event.created_at, order: .forward)],
        predicate: NSPredicate(format: "kind == 3"),
        animation: .none)
    var eventsCL: FetchedResults<Event> // CONTACT FOLLOWING CONTACTS
    
    @FetchRequest(
        entity: Event.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(format: "kind == 7"),
        animation: .none)
    var eventsR: FetchedResults<Event> // REACTIONS TO NOTES
    
    
    @EnvironmentObject var cm:ConnectionManager
    
    var body: some View {
        VStack {
            TabView {
            NavigationStack {
                MainTimelineView(contacts: contacts, events: events)
                    .navigationDestination(for: Note.self) { note in
                        NoteDetailView(note)
                    }
                    .navigationDestination(for: ContactProfile.self) { contactProfile in
                        ContactProfileView(pubkey: contactProfile.publicKey)
                    }
            }
            .tabItem { Image(systemName: "figure.fall") }
            NavigationStack {
                Playground()
                    .navigationDestination(for: Note.self) { note in
                        NoteDetailView(note)
                    }
                    .navigationDestination(for: ContactProfile.self) { contactProfile in
                        ContactProfileView(pubkey: contactProfile.publicKey)
                    }
            }
            .tabItem { Image(systemName: "lightbulb.fill") }
            .tabItem { Image(systemName: "house.fill") }
            //                Text("Notifications")
            //                    .badge(2)
            //                    .tabItem { Image(systemName: "bell.fill") }
            NavigationStack {
                AccountListView()
                Spacer()
            }
            .tabItem {
                Image(systemName: "person.badge.key.fill")
            }
            NavigationStack {
                ConfigurationView()
                Spacer()
            }
            .tabItem { Image(systemName: "server.rack") }
        }
            HStack {
                Text("C: \(contacts.count) N:\(events.count) M:\(eventsMeta.count) CL:\(eventsCL.count) R:\(eventsR.count) ALL: \(eventsAll.count)")
            }
        }
    }
    
}


private func processEvent() async { /* a lot of work */ } // Implicitly nonisolated due to being a free function

struct ContentView_Previews: PreviewProvider {
    
    static var previewUserDefaults: UserDefaults = {
                let d = UserDefaults(suiteName: "preview_user_defaults")!
                
        d.set("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", forKey: "activeAccountPublicKey")
                
        return d
            }()
    
    static var previews: some View {
        
        let accountState = AccountState(viewContext: EventsProvider.preview.container.viewContext)
        
        let cm = ConnectionManager()
        
        ContentView()
            .defaultAppStorage(previewUserDefaults)
            .environment(\.managedObjectContext,
                          EventsProvider.preview.container.viewContext)
            .environmentObject(accountState)
            .environmentObject(cm)
    }
}
