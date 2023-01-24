//
//  ContentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import CoreData

struct ContentView: View {
    
    @AppStorage("devToggle") var devToggle: Bool = false
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
    
    @State var navigateToNoteId:String? = nil
    @State var navigateToPubkey:String? = nil
    @State var urlNavigation:Bool = false
    @State var selectedTab = "MainTimeline"
    
    var body: some View {
        VStack {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    MainTimelineView(contacts: contacts, events: events)
                        .navigationDestination(for: Note.self) { note in
                            NoteDetailView(note)
                        }
                        .navigationDestination(for: ContactPubkey.self) { pubkey in
                            ProfileView(pubkey: pubkey)
                        }
                        .navigationDestination(isPresented: $urlNavigation) {
                            if (navigateToPubkey != nil) {
                                ProfileView(pubkey: navigateToPubkey!, urlNavigation: urlNavigation)
                            }
                        }
                        .onOpenURL { url in
                            // TODO: CHECK INPUT!!! SECURITY!
                            print(url.absoluteString)
                            let matches = url.absoluteString.matchingStrings(regex: "^(nostr:)(npub[0-9a-zA-Z]{59})$")
                            if matches.count == 1 && matches[0].count == 3 {
                                print("ok lets go to: \(matches[0][2])")
                                key = try! NIP19(displayString: matches[0][2])
                                print("ok lets go to: \(key.hexString)")
                                navigateToPubkey = key.hexString
                                urlNavigation = true
                                selectedTab = "MainTimeline"
                            }
                            
                        }
                        .navigationDestination(for: Contact.self) { contact in
                            ProfileView(pubkey: contact.pubkey!, contact: contact)
                        }
                }
                .tabItem { Image(systemName: "figure.fall") }
                .tag("MainTimeline")
                
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
                .tag("Playground")
                
                NavigationStack {
                    AccountListView()
                    Spacer()
                }
                .tabItem {
                    Image(systemName: "person.badge.key.fill")
                }
                .tag("Accounts")
                
                NavigationStack {
                    ConfigurationView()
                    Spacer()
                }
                .tabItem { Image(systemName: "server.rack") }
                .tag("Configuration")
            }
            if (devToggle) {
                HStack {
                    Text("C: \(contacts.count) N:\(events.count) M:\(eventsMeta.count) CL:\(eventsCL.count) R:\(eventsR.count) ALL: \(eventsAll.count)")
                }
            }
            
        }
    }
    
}


private func processEvent() async { /* a lot of work */ } // Implicitly nonisolated due to being a free function

struct ContentView_Previews: PreviewProvider {
    
    static var previews: some View {
        ContentView()
            .withPreviewEnvironment()
    }
}
