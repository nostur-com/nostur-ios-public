//
//  ProfileView.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/03/2023.
//

import SwiftUI
import Nuke
import NukeUI

struct ProfileView: View {
    @Environment(\.managedObjectContext) var viewContext
    let sp:SocketPool = .shared
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var dim:DIMENSIONS
    @ObservedObject var settings:SettingsStore = .shared
     
    @ObservedObject var contact:Contact
    var pubkey:String
    
    @FetchRequest
    var clEvents:FetchedResults<Event>
    
    @FetchRequest
    var relayEvents:FetchedResults<Event>
    
    @FetchRequest
    var kind0Events:FetchedResults<Event>
    
    @State var profilePicViewerIsShown = false
    @State var selectedSubTab = "Posts"
    @State var limit = 10
    @State var tabOffset = 0.0
    
    init(contact:Contact) {
        self.contact = contact
        self.pubkey = contact.pubkey
        
        let cl = Event.fetchRequest()
        cl.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        cl.predicate = NSPredicate(format: "pubkey == %@ AND kind == 3", pubkey)
        _clEvents = FetchRequest(fetchRequest: cl)
        
        let rl = Event.fetchRequest()
        rl.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        rl.predicate = NSPredicate(format: "pubkey == %@ AND kind == 10002", pubkey)
        _relayEvents = FetchRequest(fetchRequest: rl)
        
        let kind0 = Event.fetchRequest()
        kind0.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        kind0.predicate = NSPredicate(format: "pubkey == %@ AND kind == 0", pubkey)
        
        _kind0Events = FetchRequest(fetchRequest: kind0)
    }
    
    let PFP_SIZE = 75.0
    
    var body: some View {
        let _ = Self._printChanges()
        ScrollView {
            Color.clear.background( // GeometryReader in .background so it does not mess up layout
                GeometryReader { toolbarGEO in
                    Color.clear
                        .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            VStack {
                                HStack(spacing:2) {
                                    PFP(pubkey: contact.pubkey,
                                        pictureUrl: contact.picture,
                                        size: 25,
                                        isFollowing:ns.isFollowing(contact.pubkey)
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.systemBackground, lineWidth: 1)
                                    )
                                    Text("\(contact.authorName) ").font(.headline)
                                }
                                .offset(y: 160 + (max(-160,toolbarGEO.frame(in:.global).minY)))
                            }.frame(height: 40).clipped()
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            VStack {
                                ProfileFollowButton(contact: contact)
                                    .offset(y: 123 + (max(-123,toolbarGEO.frame(in:.global).minY)))
                            }.frame(height: 40).clipped()
                        }
                    }
                }
            )
            
            LazyVStack(alignment:.leading, spacing:0, pinnedViews: [.sectionHeaders]) {
                Section {
                    VStack {
                        GeometryReader { geoBanner in
                            ProfileBanner(banner: contact.banner, width: dim.listWidth, offset: geoBanner.frame(in:.global).minY)
                                .overlay(alignment: .bottomLeading, content: {
                                    PFP(pubkey: contact.pubkey, pictureUrl: contact.picture, size: PFP_SIZE, isFollowing:ns.isFollowing(contact.pubkey))
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.systemBackground, lineWidth: 3)
                                        )
                                        .onTapGesture {
                                            if (contact.picture != nil) {
                                                profilePicViewerIsShown = true
                                            }
                                        }
                                        .scaleEffect(min(1,max(0.5,geoBanner.frame(in:.global).minY / 70 + 1.3)), anchor:.bottom)
                                        .offset(x: 10, y: PFP_SIZE/2)
                                })
                            
                        }
                        
                        VStack(alignment: .leading) {
                            HStack(alignment:.top) {
                                if (!settings.hideBadges) {
                                    ProfileBadgesContainer(pubkey: contact.pubkey)
                                        .offset(x: 85, y: 0)
                                }
                                
                                Spacer()
                                
                                ProfileLightningButton(contact: contact)
                                
                                ProfileFollowButton(contact: contact)
                                    .padding(.trailing, 10)
                            }
                            .padding(.top, 10)
                            
                            HStack(spacing:0) {
                                Text("\(contact.authorName) ").font(.system(size: 24, weight:.bold))
                                if (contact.nip05veried) {
                                    Group {
                                        Image(systemName: "checkmark.seal.fill")
                                        Text(contact.nip05domain).font(.footnote)
                                    }.foregroundColor(Color("AccentColor"))
                                }
                            }
                            
                            HStack {
                                Text("@\(contact.username)").foregroundColor(.secondary)
                                ContactPrivateNoteToggle(contact: contact)
                                Menu {
                                    Button {
                                        UIPasteboard.general.string = contact.npub
                                    } label: {
                                        Label("Copy npub", systemImage: "doc.on.clipboard")
                                    }
                                    if let kind0 = kind0Events.first {
                                        Button {
                                            UIPasteboard.general.string = kind0.toNEvent().eventJson()
                                        } label: {
                                            Label("Copy profile source", systemImage: "doc.on.clipboard")
                                        }
                                    }
                                    
                                    
                                    Button {
                                        ns.objectWillChange.send()
                                        ns.account!.blockedPubkeys_ = ns.account!.blockedPubkeys_ + [contact.pubkey]
                                        sendNotification(.blockListUpdated, ns.account!.blockedPubkeys_)
                                    } label: {
                                        Label("Block @\(contact.username)", systemImage: "slash.circle")
                                    }
                                    Button {
                                        sendNotification(.reportContact, contact)
                                    } label: {
                                        Label("Report @\(contact.username)", systemImage: "flag")
                                    }
                                    
                                    
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .fontWeight(.bold)
                                }
                                if (ns.followsYou(contact)) {
                                    Text("Follows you").font(.system(size: 12))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary)
                                        .opacity(0.7)
                                        .cornerRadius(13)
                                }
                            }
                            
                            Text("\(String(contact.about ?? "(No information)"))\n")
                            
                            HStack(alignment: .center, spacing:0) {
                                if contact.followingPubkeys.count == 0 {
                                    ProgressView()
                                        .padding(.horizontal, 7)
                                }
                                else {
                                    Text("**\(contact.followingPubkeys.count)** ")
                                }
                                Text("Following  ")
                                
                                Text("**♾️** Followers")
                                    .onTapGesture { selectedSubTab = "Followers" }
                            }
                            .frame(height: 30)
                        }
                        .padding(10)
                        .padding(.top, 120)
                    }
                }
                Section {
                    VStack {
                        switch selectedSubTab {
                            case "Posts":
                                ProfileNotesView(pubkey: pubkey)
                            case "Following":
                                VStack {
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
                                                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: pubkey)))
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
        .onReceive(receiveNotification(.newFollowingListFromRelay)) { notification in
            let nEvent = notification.object as! NEvent
            if nEvent.publicKey == contact.pubkey {
                contact.objectWillChange.send()
            }
        }
        .task {
//            return
            if (NIP05.shouldVerify(contact)) {
                if (await NIP05.verify(nip05: contact.nip05!, expectedPubkey: contact.pubkey)) {
                    await viewContext.perform {
                        contact.nip05verifiedAt = Date.now
                        do { try viewContext.save() }
                        catch { print("1) What") }
                    }
                    print("👍👍 nip05 verified \(contact.pubkey) \(contact.nip05!) ")
                }
            }
        }
        .task {
//            return
            guard contact.anyLud else { return }
            do {
                if let lud16 = contact.lud16, lud16 != "" {
                    let response = try await LUD16.getCallbackUrl(lud16: lud16)
                    await MainActor.run {
                        if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                            contact.zapperPubkey = response.nostrPubkey!
                            print("contact.zapperPubkey updated: \(response.nostrPubkey!)")
                        }
                    }
                }
                else if let lud06 = contact.lud06, lud06 != "" {
                    let response = try await LUD16.getCallbackUrl(lud06: lud06)
                    await MainActor.run {
                        if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                            contact.zapperPubkey = response.nostrPubkey!
                            print("contact.zapperPubkey updated: \(response.nostrPubkey!)")
                        }
                    }
                }
            }
            catch {
                print("problem in lnurlp")
                print(error)
            }
        }
        .onChange(of: contact.nip05) { nip05 in
//            return
            if (NIP05.shouldVerify(contact)) {
                Task {
                    if (await NIP05.verify(nip05: contact.nip05!, expectedPubkey: contact.pubkey)) {
                        await viewContext.perform {
                            contact.nip05verifiedAt = Date.now
                            do { try viewContext.save() }
                            catch { print("w🚗at") }
                        }
                        print("👍👍 nip05 verified \(contact.pubkey) \(contact.nip05!) ")
                    }
                }
            }
        }
        .task {
//            return
            //            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadataAndBadges(pubkey: pubkey)))
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserProfileKinds(pubkey: pubkey, kinds: [0,3,30008,10002])))
        }
        .fullScreenCover(isPresented: $profilePicViewerIsShown) {
            ProfilePicFullScreenSheet(profilePicViewerIsShown: $profilePicViewerIsShown, pictureUrl:contact.picture!, isFollowing: ns.isFollowing(contact.pubkey))
        }
//        .navigationBarHidden(true)
//        .ignoresSafeArea(edges: .top)
//        .edgesIgnoringSafeArea(.top)
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
//        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
                let f = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
//        let snowden = PreviewFetcher.fetchContact(pubkey)
        
//        let testgif = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"

        NavigationStack {
            if let contact = PreviewFetcher.fetchContact(f) {
                ProfileView(contact: contact)
            }
        }
        .withPreviewEnvironment()
    }
}


struct OffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    
    static func reduce(value: inout CGFloat     , nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
