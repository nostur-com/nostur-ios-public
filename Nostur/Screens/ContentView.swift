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
    @EnvironmentObject var ns:NosturState
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @State var path = NavigationPath()
    
    var cm:SocketPool = .shared
//    @EnvironmentObject var cm:ConnectionManager
    @State var selectedTab = "MainTimeline"
    @State var navigationPath = NavigationPath()
    @AppStorage("showReplies") var showReplies = true
    
    var body: some View {
        VStack {
            TabView(selection: $selectedTab) {
                NavigationStack(path: $navigationPath) {
                    VStack {
                        
                        let followingPubkeys = [String](ns.followingPublicKeys)
                        TimelineFRControllerView(followingPubkeys: followingPubkeys, showReplies:showReplies)
//                        MainTimelineView(followingPubkeys: followingPubkeys, showReplies: showReplies)
//                        NaturalTimelineView(showReplies: true)
                    }
                        .onOpenURL { url in
                            // TODO: CHECK INPUT!!! SECURITY!
                            print(url.absoluteString)
                            let nostr = url.absoluteString.matchingStrings(regex: "^(nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$")
                            if nostr.count == 1 && nostr[0].count == 4 {
                                print("ok lets go to: \(nostr[0][2])\(nostr[0][3])")
                                let key = try! NIP19(displayString: "\(nostr[0][2])\(nostr[0][3])")
                                print("ok lets go to: \(key.hexString)")
                                if nostr[0][2] == "npub1" {
                                    navigationPath.append(ContactPath(key: key.hexString))
                                }
                                if nostr[0][2] == "note1" {
                                    navigationPath.append(NotePath(id: key.hexString))
                                }
                                selectedTab = "MainTimeline"
//                                navigationPath.append(key.hexString)
                            }
                            
                            let nostur = url.absoluteString.matchingStrings(regex: "^(nostur:)(p:|e:)([0-9a-z]{64})$")
                            if nostur.count == 1 && nostur[0].count == 4 {
                                print("ok lets go to: \(nostur[0][2])\(nostur[0][3])")
                                if nostur[0][2] == "p:" {
                                    navigationPath.append(ContactPath(key: nostur[0][3]))
                                }
                                if nostur[0][2] == "e:" {
                                    navigationPath.append(NotePath(id: nostur[0][3]))
                                }
                                selectedTab = "MainTimeline"
//                                navigationPath.append(key.hexString)
                            }                            //
                            
                        }
                        .navigationDestination(for: NotePath.self) { path in
                            NoteById(id: path.id)
                        }
                        .navigationDestination(for: Event.self) { event in
                            NoteDetail(event: event)
                        }
                        .navigationDestination(for: ContactPath.self) { path in
                            ProfileByPubkey(pubkey: path.key)
                        }
                        .navigationDestination(for: Contact.self) { contact in
                            Profile(contact: contact)
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
                    if (ns.account != nil) {
                        BookmarksView(account: ns.account!)
                            .navigationDestination(for: NotePath.self) { path in
                                NoteById(id: path.id)
                            }
                            .navigationDestination(for: Event.self) { event in
                                NoteDetail(event: event)
                            }
                            .navigationDestination(for: ContactPath.self) { path in
                                ProfileByPubkey(pubkey: path.key)
                            }
                            .navigationDestination(for: Contact.self) { contact in
                                Profile(contact: contact)
                            }
                    }
                    else {
                        Text("Select account account first on accounts tab.")
                    }
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
            .background(.regularMaterial)
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
