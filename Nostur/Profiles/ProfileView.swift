//
//  ProfileView.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/01/2023.
//

import SwiftUI
import NukeUI
import Nuke

// Navigation values:
//typealias ContactPubkey

struct ContactList: View {
    
    @FetchRequest
    var contacts:FetchedResults<Contact>
    var pubkeys:[String]

    init(pubkeys:[String]) {
        self.pubkeys = pubkeys
        
        _contacts = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "pubkey IN %@", pubkeys),
            animation: .none)
    }
    
    var body: some View {
        LazyVStack {
            Text("Total: \(contacts.count)")
            ForEach(contacts) { contact in
                ProfileRow(contact: contact)
            }
            
            // TODO: ForEach for Fake ProfileRow view for pubkeys not in Contact
            
            let missing = pubkeys.filter { pubkey in
                contacts.map { $0.pubkey! }.firstIndex(of: pubkey) == nil
            }
            
            VStack {
                Text("Missing: \(missing.count)")
                ForEach(missing, id:\.self) { pubkey in
                    Text("Missing: \(pubkey)")
                }
            }
            
        }.onAppear {
            // fetch missing
            // fetch pubkeys not in [contacts.pubkey]
        }
    }
    
}


struct ProfileView: View {
    
    @EnvironmentObject var accountState:AccountState
    @EnvironmentObject var cm:ConnectionManager
    
    var pubkey:String
    
    @FetchRequest
    var contacts:FetchedResults<Contact>
    
    @FetchRequest
    var clEvents:FetchedResults<Event>
    
    @State var notesTab = true
    @State var followersTab = false
    
    
    init(pubkey:String) {
        self.pubkey = pubkey
        
        _clEvents = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
            predicate: NSPredicate(format: "pubkey == %@ AND kind == 3", pubkey)
        )
        
        _contacts = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "pubkey == %@", pubkey)
        )
    }
    
    var body: some View {
        ScrollView {
            ZStack() {
                GeometryReader { geo in
                    if (contacts.first?.banner != nil) {
                        
                        LazyImage(url: URL(string: contacts.first!.banner!)) { state in
                            if let image = state.image {
                                image // Displays the loaded image
                            }
                            else {
                                Image("NosturBanner")
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geo.size.width, height: 150)
                                //                                .clipped()
                            }
                        }
                        .processors([ImageProcessors.Resize(width: geo.size.width)])
                        .animation(nil)
                        .priority(.high)
                        .pipeline(ImagePipeline {
                            // TODO: volgens mij klopt niet
                            /// moet ergens anders clean 1x doen ipv iedere keer voor image
                            $0.dataLoader = DataLoader(configuration: {
                                // Disable disk caching built into URLSession
                                let conf = DataLoader.defaultConfiguration
                                conf.urlCache = nil
                                return conf
                            }())
                            
                            $0.imageCache = ImageCache()
                            $0.dataCache = try! DataCache(name: "com.nostur.2140.banner")
                        }).frame(width: geo.size.width, height: 150)
                        //                            .clipped()
                        
                    }
                    else {
                        HStack {
                            Image("NosturBanner")
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: 150)
                        }
                    }
                }
                
                HStack {
                    VStack {
                        ProfilePicView(pubkey: pubkey, contact: contacts.first)
                            .frame(maxWidth:75, maxHeight:75)
                            .clipShape(Circle())
                            .offset(x: 10, y: 150-37.5)
                        Spacer()
                    }
                    Spacer()
                }
                
                VStack(alignment: .leading) {
                    Rectangle().background(.clear).foregroundColor(.clear).frame(height:150) // Spacer to push content below header pic
                    
                    HStack(alignment:.top) {
                        
                        Spacer()
                        
                        Button {
                            if accountState.isFollowing(pubkey) {
                                accountState.unfollow(pubkey)
                            } else {
                                accountState.follow(pubkey, cm: cm)
                            }
                        } label: {
                            Text(accountState.isFollowing(pubkey) ? "Following" : "Follow")
                                .frame(height: 30)
                                .padding(.horizontal, 25)
                            //.padding(.vertical, 10)
                                .font(.caption.weight(.bold))
                                .foregroundColor(.primary)
                                .background(.clear)
                                .cornerRadius(20)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.primary, lineWidth: 1)
                                }
                        }
                    }
                    
                    
                    Text("\(contacts.first?.authorName ?? "Anon")").font(.headline)
                    HStack {
                        Text("@\(contacts.first?.username ?? String(pubkey.prefix(5)) )").foregroundColor(.secondary)
                        
                        Menu {
                            Button {
                                UIPasteboard.general.string = pubkey
                            } label: {
                                Label("Copy public key hex \(pubkey)...", systemImage: "doc.on.clipboard")
                            }
                            Button {
                                UIPasteboard.general.string = Contact.npub(pubkey)
                            } label: {
                                Label("Copy npub \(Contact.npub(pubkey))...", systemImage: "doc.on.clipboard")
                            }
                        } label: {
                            Image(systemName: "person.badge.key.fill")
                            //                            Text("···")
                            //                                .foregroundColor(.secondary)
                            //                                .padding(.top, 0)
                            //                                .padding(.bottom, 10)
                            //                                .padding(.leading, 20)
                            //                                .padding(.trailing, 10)
                            
                        }
                        
                    }
                    
                    
                    Text("\n\(String(contacts.first?.about ?? "(No information)"))")
                    
                    //                Text("Followed by ppl you know...")
                    // Tweets here
                    Text("Tweets / Liked").font(.headline).fontWeight(.heavy).padding(.vertical, 10)
                    
                    
                    ControlGroup {
                        Toggle(isOn: $notesTab) {
                            Label("Notes", systemImage: "bubble.left.and.bubble.right")
                        }.toggleStyle(.button)
                        Toggle(isOn: $followersTab) {
                            Label("Followers", systemImage: "person.3.sequence")
                        }.toggleStyle(.button)
                    }
                    
                    
                    if (followersTab) {
                        VStack {
                            if clEvents.count != 0, let pubkeys = clEvents.first!.contactPubkeys() {
                                
                                Text("Following").font(.headline).fontWeight(.heavy).padding(.vertical, 10)
                                
                                ContactList(pubkeys: pubkeys)
                                
//                                LazyVStack {
//                                    ForEach(pubkeys.indices, id: \.self) { index in
//                                        ProfileRowView(pubkey: pubkeys[index])
//                                            .onAppear {
//                                                // dont prefetch first 5
//                                                // will probably already be visible and fetched by its own .onAppear
//
//                                                if (index > 5) {
//                                                    // TODO: find out logic for prefetching next profile info but not if already in cache but also refetch if too old
//                                                }
//                                            }
//                                        Divider()
//                                    }
//                                    // TODO: onAppear, take index. prefetch next 10.....
//                                }
                                
//                                Spacer()
                            }
                            else {
                                Text("Could not find list of contacts followed by @\( contacts.first?.username ?? String(pubkey.prefix(5)) )")
                                    .onAppear {
                                        print("🟢 ProfileView.onAppear no clEvent so REQ.3: \(pubkey)")
                                        cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: pubkey)))
                                    }
                            }
                        }
                        .onAppear {
                            notesTab = false
                        }
                    }
                    
                    if (notesTab) {
                        ProfileNotesView(pubkey: pubkey)
                            .onAppear {
                                followersTab = false
                            }
                    }
                    
                    
                    
                    
                }.padding(10)
//                Spacer()
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            print("fetching kind=0 for \(pubkey)")
            print("🟢🟢🟢 ProfileView.onAppear ALWAYS REQ.0: \(pubkey)")
            cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: pubkey)))
        }
    }
}

struct OnlyPubkey_Previews: PreviewProvider {
    static var previews: some View {
        // 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0 // bitcoiner
        let pubkey = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
        
        ProfileView(pubkey: pubkey)
            .withPreviewEnvironment()
    }
}

struct NoClEvent_Previews: PreviewProvider {
    static var previews: some View {
        // 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0 // bitcoiner
        let pubkey = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
        //        let contact = PreviewFetcher.fetchContact(pubkey)
        
        ProfileView(pubkey: pubkey)
            .withPreviewEnvironment()
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        // 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0 // bitcoiner
        // snowden: 84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240
        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
        //        let contact = PreviewFetcher.fetchContact(pubkey)
        //        let clEvent = PreviewFetcher.fetchEvents(pubkey, kind: 3).first!
        //
        ProfileView(pubkey: pubkey)
            .withPreviewEnvironment()
    }
}
