//
//  ContentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import CoreData

struct NotePath: Hashable {
    var id:String
}

struct ContactPath: Hashable {
    var key:String
}

struct ContentView: View {
    
    @AppStorage("devToggle") var devToggle: Bool = false
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var accountState:AccountState
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @State var path = NavigationPath()
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Contact.updated_at, order: .reverse)],
        animation: .none)
    var contacts:FetchedResults<Contact> // ALL CONTACTS
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Event.created_at, order: .forward)],
        predicate: NSPredicate(format: "kind == 1 && replyToId == nil"),
        animation: .none)
    var events: FetchedResults<Event> // NOTES (NOT REPLIES)
    
    @FetchRequest(
        //        entity: Event.entity(),
        //        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        sortDescriptors: [SortDescriptor(\Event.created_at, order: .forward)],
        predicate: NSPredicate(format: "kind == 1"),
        animation: .none)
    var eventsAll: FetchedResults<Event> // NOTES AND REPLIES
    
    @EnvironmentObject var cm:ConnectionManager
    @State var selectedTab = "MainTimeline"
    @State var navigationPath = NavigationPath()
    @AppStorage("showReplies") var showReplies = false
    
    var body: some View {
        VStack {
            TabView(selection: $selectedTab) {
                NavigationStack(path: $navigationPath) {
                    MainTimelineView(showReplies: $showReplies, contacts: contacts, events: showReplies ? eventsAll : events)
                        .onOpenURL { url in
                            // TODO: CHECK INPUT!!! SECURITY!
                            print(url.absoluteString)
                            let matches = url.absoluteString.matchingStrings(regex: "^(nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$")
                            if matches.count == 1 && matches[0].count == 4 {
                                print("ok lets go to: \(matches[0][2])\(matches[0][3])")
                                key = try! NIP19(displayString: "\(matches[0][2])\(matches[0][3])")
                                print("ok lets go to: \(key.hexString)")
                                if matches[0][2] == "npub1" {
                                    navigationPath.append(ContactPath(key: key.hexString))
                                }
                                if matches[0][2] == "note1" {
                                    navigationPath.append(NotePath(id: key.hexString))
                                }
                                selectedTab = "MainTimeline"
//                                navigationPath.append(key.hexString)
                            }
                            
                        }
                        .navigationDestination(for: NotePath.self) { path in
                            NoteDetailView(id: path.id)
                        }
                        .navigationDestination(for: ContactPath.self) { path in
                            ProfileView(pubkey: path.key)
                        }
                        .navigationDestination(for: Contact.self) { contact in
                            ProfileView(pubkey: contact.pubkey!)
                        }
                }
                .tabItem { Image(systemName: "house.fill") }
                .tag("MainTimeline")
                
                NavigationStack {
                    AccountListView()
                    Spacer()
                }
                .tabItem {
                    Image(systemName: "person.badge.key.fill")
                }
                .tag("Accounts")
                
                NavigationStack {
                    BookmarksView()
                    Spacer()
                }
                .tabItem { Image(systemName: "bookmark.circle") }
                .tag("Bookmarks")
                
                NavigationStack {
                    ConfigurationView()
                    Spacer()
                }
                .tabItem { Image(systemName: "server.rack") }
                .tag("Configuration")
            }
            if (devToggle) {
                HStack {
//                    Text("C: \(contacts.count) N:\(events.count) M:\(eventsMeta.count) CL:\(eventsCL.count) R:\(eventsR.count) ALL: \(eventsAll.count)")
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
