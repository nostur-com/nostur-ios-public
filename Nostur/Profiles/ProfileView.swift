//
//  ProfileView.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/03/2023.
//

import SwiftUI
import Nuke
import NukeUI
//import AnimatedImage

struct ProfileByPubkey: View {
    
    let sp:SocketPool = .shared
    @EnvironmentObject var ns:NosturState
     
    
    var pubkey:String
    
    @FetchRequest
    var contacts:FetchedResults<Contact>
    
    let timeOut = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    
    @State var editingAccount:Account?
    
    init(pubkey:String) {
        self.pubkey = pubkey
        
        _contacts = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
            predicate: NSPredicate(format: "pubkey == %@", pubkey)
        )
    }
    
    var body: some View {
        if let contact = contacts.first {
            ProfileView(contact: contact)
        }
        else {
            ProgressView().onAppear {
                print("🟢 ProfileByPubkey.onAppear no contact so REQ.0: \(pubkey)")
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: pubkey)))
            }
            .sheet(item: $editingAccount) { account in
                NavigationStack {
                    AccountEditView(account: account)
                }
            }
            .onReceive(timeOut) { firedDate in
                timeOut.upstream.connect().cancel()
                if ns.account?.publicKey == pubkey {
                    editingAccount = ns.account!
                }
            }
        }
    }
}

struct ProfileView: View {
    @Environment(\.managedObjectContext) var viewContext
    let sp:SocketPool = .shared
    @EnvironmentObject var ns:NosturState
     
    @ObservedObject var contact:Contact
    var pubkey:String
    let hideBadges:Bool
    
    @FetchRequest
    var clEvents:FetchedResults<Event>
    
    @FetchRequest
    var relayEvents:FetchedResults<Event>
    
    @FetchRequest
    var kind0Events:FetchedResults<Event>
    
    @State var isFollowing = false
    @State var profilePicViewerIsShown = false
    @State var selectedSubTab = "Posts"
    @State var limit = 10
    @State var tabOffset = 0.0
    @State var editingAccount:Account?
    
    init(contact:Contact) {
        self.contact = contact
        self.pubkey = contact.pubkey
        self.hideBadges = SettingsStore.shared.hideBadges
        
        _clEvents = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
            predicate: NSPredicate(format: "pubkey == %@ AND kind == 3", pubkey)
        )
        
        _relayEvents = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
            predicate: NSPredicate(format: "pubkey == %@ AND kind == 10002", pubkey)
        )
        
        _kind0Events = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
            predicate: NSPredicate(format: "pubkey == %@ AND kind == 0", pubkey)
        )
    }
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                LazyVStack(alignment:.leading, spacing:0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        VStack {
                            ZStack {
                                if let banner = contact.banner {
                                    if (banner.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                                        LazyImage(url: URL(string: banner)) { state in
                                            if let container = state.imageContainer {
                                                if container.type == .gif, let gifData = container.data {
                                                    AnimatedGifView(gifData: gifData, width: geo.size.width, height: 150)
                                                        .frame(width: geo.size.width, height: 150)
                                                        .clipped()
                                                        .ignoresSafeArea(edges: .top)
                                                    
                                                }
                                                else if let image = state.image {
                                                    image
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: geo.size.width, height: 150)
                                                        .clipped()
                                                        .ignoresSafeArea(edges: .top)
                                                }
                                                else {
                                                    HStack {
                                                        Rectangle()
                                                            .foregroundColor(.gray)
                                                            .frame(width: geo.size.width, height: 150)
                                                            .ignoresSafeArea(edges: .top)
                                                    }
                                                }
                                            }
                                            else {
                                                HStack {
                                                    Rectangle()
                                                        .foregroundColor(.gray)
                                                        .frame(width: geo.size.width, height: 150)
                                                        .ignoresSafeArea(edges: .top)
                                                }
                                            }
                                        }
                                        .pipeline(ImageProcessing.shared.banner) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
                                        //                                        .priority(.low) // lower prio for animated gif, saves bandwidth?
                                    }
                                    else {
                                        LazyImage(url: URL(string: banner)) { state in
                                            if let image = state.image {
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: geo.size.width, height: 150)
                                                    .clipped()
                                                    .ignoresSafeArea(edges: .top)
                                            }
                                            else {
                                                HStack {
                                                    Rectangle()
                                                        .foregroundColor(.gray)
                                                        .frame(width: geo.size.width, height: 150)
                                                        .ignoresSafeArea(edges: .top)
                                                }
                                            }
                                        }
                                        //                                        .processors([.resize(height: 150)])
                                        .pipeline(ImageProcessing.shared.banner)
                                        //                    .priority(.low)
                                    }
                                }
                                else {
                                    HStack {
                                        Rectangle()
                                            .foregroundColor(.gray)
                                            .frame(width: geo.size.width, height: 150)
                                        //                                            .ignoresSafeArea(edges: .top)
                                    }
                                    .ignoresSafeArea(edges: .top)
                                }
                                
                                HStack {
                                    VStack {
                                        PFP(pubkey: contact.pubkey, pictureUrl: contact.picture, size: 75)
                                            .offset(x: 10, y: 150-37.5)
                                            .onTapGesture {
                                                if (contact.picture != nil) {
                                                    profilePicViewerIsShown = true
                                                }
                                            }
                                        Spacer()
                                    }
                                    Spacer()
                                }
                            }
                            
                            VStack(alignment: .leading) {
                                HStack(alignment:.top) {
                                    if (!hideBadges) {
                                        ProfileBadgesContainer(pubkey: contact.pubkey)
                                            .offset(x: 85, y: 0)
                                    }
                                    
                                    Spacer()
                                    
                                    ProfileLightningButton(contact: contact)
                                    
                                    if (contact.pubkey != ns.account?.publicKey) {
                                        Button {
                                            if (isFollowing) {
                                                isFollowing = false
                                                ns.unfollow(contact)
                                            }
                                            else {
                                                print("chaning isFollowing to true 1")
                                                isFollowing = true
                                                ns.follow(contact)
                                                print("chaning isFollowing to true 2")
                                                //                                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: pubkey)))
                                            }
                                        } label: {
                                            FollowButton(isFollowing:isFollowing)
                                        }
                                        .onAppear {
                                            if (ns.isFollowing(contact)) {
                                                isFollowing = true
                                            }
                                        }
                                    }
                                    else {
                                        Button {
                                            if let account = ns.account {
                                                editingAccount = account
                                            }
                                        } label: {
                                            Text("Edit profile")
                                        }
                                        .buttonStyle(NosturButton())
                                    }
                                }
                                
                                HStack(spacing:1) {
                                    Text("\(contact.authorName) ").font(.headline)
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
                                            UIPasteboard.general.string = Contact.npub(pubkey)
                                        } label: {
                                            Label("Copy npub \(String(Contact.npub(pubkey).prefix(11)))...", systemImage: "doc.on.clipboard")
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
                                
                                Text("\n\(String(contact.about ?? "(No information)"))")
                                
                                HStack {
                                    Text("\n**\(contact.followingPubkeys.count)** Following")
                                    
                                    Text("\n**♾️** Followers")
                                        .onTapGesture {
                                            selectedSubTab = "Followers"
                                        }
                                    //                        Text("\n**\(contact.followingPubkeys.count)** Followers")
                                }
                                //                                Spacer()
                            }
                            .padding(10)
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
                                            
                                            Text("Following").font(.headline).fontWeight(.heavy).padding(.vertical, 10)
                                            
                                            ContactList(pubkeys: pubkeys)
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
                                case "Likes":
                                    ProfileLikesView(pubkey: pubkey)
                                case "Zaps":
                                    ProfileZapsView(pubkey:pubkey, contact: contact)
                                case "Relays":
                                    VStack {
                                        if relayEvents.count != 0 {
                                            ProfileRelays(relayEvent: relayEvents.first!)
                                        }
                                        else if clEvents.count != 0 {
                                            ProfileRelaysView(clEvent: clEvents.first!)
                                        }
                                        else {
                                            HStack {
                                                Spacer()
                                                ProgressView()
                                                    .padding(50)
                                                Spacer()
                                            }
                                            .onAppear {
                                                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserProfileKinds(pubkey: pubkey, kinds: [10002])))
                                                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: pubkey)))
                                            }
                                        }
                                    }
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
                        HStack {
                            TabButton(
                                action: { selectedSubTab = "Posts" },
                                title: "Posts",
                                selected: selectedSubTab == "Posts")
                            TabButton(
                                action: { selectedSubTab = "Following" },
                                title: "Following",
                                selected: selectedSubTab == "Following")
                            TabButton(
                                action: { selectedSubTab = "Likes" },
                                title: "Likes",
                                selected: selectedSubTab == "Likes")
                            TabButton(
                                action: { selectedSubTab = "Zaps" },
                                title: "Zaps",
                                selected: selectedSubTab == "Zaps")
                            TabButton(
                                action: { selectedSubTab = "Relays" },
                                title: "Relays",
                                selected: selectedSubTab == "Relays")
                        }
                        .padding(.top, 10)
                        .background(.regularMaterial)
                    }
                }
            }
        }
        .task {
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
            //            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadataAndBadges(pubkey: pubkey)))
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserProfileKinds(pubkey: pubkey, kinds: [0,3,30008,10002])))
        }
        .fullScreenCover(isPresented: $profilePicViewerIsShown) {
            ProfilePicFullScreenSheet(profilePicViewerIsShown: $profilePicViewerIsShown, pictureUrl:contact.picture!)
        }
        .sheet(item: $editingAccount) { account in
            NavigationStack {
                AccountEditView(account: account)
            }
        }
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
        //        let f = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
        let snowden = PreviewFetcher.fetchContact(pubkey)
        //        let fabian = PreviewFetcher.fetchContact(f)
        
        Group {
            if let contact = snowden {
                NavigationStack {
                    ProfileView(contact: contact)
                }
            }
            
            //            NavigationStack {
            //                if let contact = fabian {
            //                    ProfileView(contact: contact)
            //                }
            //            }
        }
        .withPreviewEnvironment()
    }
}
