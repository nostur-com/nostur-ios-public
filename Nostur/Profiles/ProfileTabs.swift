//
//  ProfileTabs.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/05/2023.
//

import SwiftUI

struct ProfileTabs: View {
    
    @ObservedObject var contact:Contact
    var pubkey:String { contact.pubkey }
    @Binding var selectedSubTab:String
    @EnvironmentObject var dim:DIMENSIONS
    
    @FetchRequest
    var clEvents:FetchedResults<Event>
    
    init(contact: Contact, selectedSubTab:Binding<String>) {
        self.contact = contact
        self._selectedSubTab = selectedSubTab
        let cl = Event.fetchRequest()
        cl.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        cl.predicate = NSPredicate(format: "pubkey == %@ AND kind == 3", contact.pubkey)
        _clEvents = FetchRequest(fetchRequest: cl)
    }
    
    var body: some View {
        Section {
            VStack {
                switch selectedSubTab {
                    case "Posts":
                        ProfileNotesView(pubkey: pubkey)
                    case "Following":
                        LazyVStack {
                            if clEvents.count != 0, let pubkeys = clEvents.first!.contactPubkeys() {
                                
                                let silentFollows = clEvents.first!.pubkey == NosturState.shared.pubkey ? NosturState.shared.account?.follows_.filter { $0.privateFollow }.map { $0.pubkey } : []
                                
                                ContactList(pubkeys: pubkeys, silent:silentFollows)
                            }
                            else {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .padding(50)
                                    Spacer()
                                        .onAppear {
                                            print("🟢 ProfileView.onAppear no clEvent so REQ.3: \(pubkey)")
                                            req(RM.getAuthorContactsList(pubkey: pubkey))
                                        }
                                }
                            }
                        }
                    case "Media":
                        ProfileMediaView(pubkey: pubkey)
                    case "Likes":
                        ProfileLikesView(pubkey: pubkey)
                    case "Zaps":
                        ProfileZaps(pubkey: pubkey, contact: contact)
//                                ProfileZapsView(pubkey:pubkey, contact: contact)
//                            case "Relays":
//                                VStack {
//                                    if relayEvents.count != 0 {
//                                        ProfileRelays(relayEvent: relayEvents.first!)
//                                    }
//                                    else if clEvents.count != 0 {
//                                        ProfileRelaysView(clEvent: clEvents.first!)
//                                    }
//                                    else {
//                                        HStack {
//                                            Spacer()
//                                            ProgressView()
//                                                .padding(50)
//                                            Spacer()
//                                        }
//                                        .onAppear {
//                                            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserProfileKinds(pubkey: pubkey, kinds: [10002])))
//                                            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: pubkey)))
//                                        }
//                                    }
//                                }
                    case "Followers":
                        VStack {
                            Text("Followers").font(.headline).fontWeight(.heavy).padding(.vertical, 10)
                            FollowersList(pubkey: contact.pubkey)
                        }
                    default:
                        Text("🥪")
                }
            }
        } header: {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing:0) {
                    TabButton(
                        action: { selectedSubTab = "Posts" },
                        title: "Posts",
                        selected: selectedSubTab == "Posts")
                    Spacer()
                    TabButton(
                        action: { selectedSubTab = "Following" },
                        title: "Following",
                        selected: selectedSubTab == "Following")
                    Spacer()
                    TabButton(
                        action: { selectedSubTab = "Media" },
                        title: "Media",
                        selected: selectedSubTab == "Media")
                    Spacer()
                    TabButton(
                        action: { selectedSubTab = "Likes" },
                        title: "Likes",
                        selected: selectedSubTab == "Likes")
                    Spacer()
                    TabButton(
                        action: { selectedSubTab = "Zaps" },
                        title: "Zaps",
                        selected: selectedSubTab == "Zaps")
                    //                                Spacer()
                    //                                TabButton(
                    //                                    action: { selectedSubTab = "Relays" },
                    //                                    title: "Relays",
                    //                                    selected: selectedSubTab == "Relays")
                }
                .frame(width: dim.listWidth)
            }
            .padding(.top, 10)
            .background(Color.systemBackground)
        }
    }
}

struct ProfileTabs_Previews: PreviewProvider {
    static var previews: some View {
        let f = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
        //        let snowden = PreviewFetcher.fetchContact(pubkey)
        //        let testgif = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        
        ScrollView {
            if let contact = PreviewFetcher.fetchContact(f) {
                ProfileTabs(contact: contact, selectedSubTab: .constant("Posts"))
            }
        }
        .withPreviewEnvironment({ pe in
            pe.loadContacts()
//            pe.loadPosts()
        })
    }
}
